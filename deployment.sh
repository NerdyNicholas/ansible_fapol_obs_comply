#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(pwd)/observe"
ROLES_DIR="$BASE_DIR/roles"
OBSERVE_DIR="$ROLES_DIR/rhel9_observe/tasks"
REMEDIATE_DIR="$ROLES_DIR/rhel9_remediate/tasks"
GROUP_VARS_DIR="$BASE_DIR/group_vars"

echo "[+] Creating directory structure"
mkdir -p "$OBSERVE_DIR" "$REMEDIATE_DIR" "$GROUP_VARS_DIR"

########################################
# group_vars
########################################
cat > "$GROUP_VARS_DIR/all.yml" << 'EOF'
splunk_hec_url: "https://127.0.0.1:8088/services/collector"
splunk_hec_token: "CHANGEME"
splunk_validate_certs: false

golden_host: "localhost"

fapolicyd_threshold: 5
EOF

########################################
# OBSERVE ROLE
########################################
cat > "$OBSERVE_DIR/main.yml" << 'EOF'
- import_tasks: collect.yml
- import_tasks: normalize.yml
- import_tasks: baseline.yml
EOF

cat > "$OBSERVE_DIR/collect.yml" << 'EOF'
- name: Collect journal warnings/errors
  ansible.builtin.command: >
    journalctl -p warning..emerg --since "1 hour ago" --no-pager
  register: journal_logs
  changed_when: false
  failed_when: false

- name: Collect fapolicyd logs
  ansible.builtin.command: >
    journalctl -u fapolicyd --since "1 hour ago" --no-pager
  register: fapolicyd_logs
  changed_when: false
  failed_when: false

- name: Get crypto policy
  ansible.builtin.command: update-crypto-policies --show
  register: crypto_policy
  changed_when: false

- name: Get SELinux mode
  ansible.builtin.command: getenforce
  register: selinux_mode
  changed_when: false

- name: Get FIPS state
  ansible.builtin.slurp:
    src: /proc/sys/crypto/fips_enabled
  register: fips_state

- name: Gather services
  ansible.builtin.service_facts:
EOF

cat > "$OBSERVE_DIR/normalize.yml" << 'EOF'
- name: Normalize data
  ansible.builtin.set_fact:
    observe_data:
      host: "{{ inventory_hostname }}"
      crypto_policy: "{{ crypto_policy.stdout | default('unknown') }}"
      selinux: "{{ selinux_mode.stdout | default('unknown') }}"
      fips: "{{ (fips_state.content | b64decode | trim) }}"
      journal: "{{ journal_logs.stdout_lines | default([]) }}"
      fapolicyd: "{{ fapolicyd_logs.stdout_lines | default([]) }}"
EOF

cat > "$OBSERVE_DIR/baseline.yml" << 'EOF'
- name: Set golden data
  ansible.builtin.set_fact:
    golden_data: "{{ observe_data }}"
  when: inventory_hostname == golden_host

- name: Share golden data
  ansible.builtin.set_fact:
    golden_data: "{{ hostvars[golden_host].observe_data }}"
  when: inventory_hostname != golden_host

- name: Compute drift safely
  ansible.builtin.set_fact:
    drift:
      crypto: "{{ observe_data.crypto_policy != golden_data.crypto_policy }}"
      selinux: "{{ observe_data.selinux != golden_data.selinux }}"
      fips: "{{ observe_data.fips != golden_data.fips }}"
EOF

########################################
# REMEDIATE ROLE
########################################
cat > "$REMEDIATE_DIR/main.yml" << 'EOF'
- import_tasks: remediate.yml
- import_tasks: fapolicyd_learn.yml
EOF

cat > "$REMEDIATE_DIR/remediate.yml" << 'EOF'
- name: Fix crypto drift
  ansible.builtin.command: >
    update-crypto-policies --set {{ golden_data.crypto_policy }}
  when: drift.crypto | bool
  changed_when: true

- name: Enforce SELinux
  ansible.builtin.command: setenforce 1
  when:
    - drift.selinux | bool
    - golden_data.selinux == "Enforcing"
  changed_when: true
EOF

########################################
# SAFE FAPOLICYD LEARNING
########################################
cat > "$REMEDIATE_DIR/fapolicyd_learn.yml" << 'EOF'
- name: Extract denied lines
  ansible.builtin.set_fact:
    deny_lines: "{{ observe_data.fapolicyd | select('search','denied') | list }}"

- name: Extract paths safely
  ansible.builtin.set_fact:
    denied_paths: >-
      {{
        deny_lines
        | map('regex_search','path=([^ ]+)')
        | select('string')
        | list
      }}

- name: Filter unsafe paths
  ansible.builtin.set_fact:
    safe_paths: >-
      {{
        denied_paths
        | reject('search','^/tmp')
        | reject('search','^/var/tmp')
        | reject('search','^/dev/shm')
        | list
      }}

- name: Count occurrences safely
  ansible.builtin.set_fact:
    path_counts: "{{ path_counts | default({}) | combine({item: (path_counts[item]|default(0)) + 1}) }}"
  loop: "{{ safe_paths }}"
  loop_control:
    label: "{{ item }}"

- name: Select frequent paths
  ansible.builtin.set_fact:
    frequent_paths: >-
      {{
        path_counts | dict2items
        | selectattr('value','>=',fapolicyd_threshold)
        | map(attribute='key')
        | list
      }}

- name: Write candidate rules
  ansible.builtin.copy:
    dest: /var/tmp/fapolicyd_candidates.rules
    content: "{{ frequent_paths | map('regex_replace','^(.*)$','allow perm=execute path=\\1') | join('\n') }}"
    mode: '0600'
  when: frequent_paths | length > 0
EOF

########################################
# PLAYBOOKS
########################################
cat > "$BASE_DIR/observe.yml" << 'EOF'
- hosts: all
  become: true
  gather_facts: true
  roles:
    - rhel9_observe
EOF

cat > "$BASE_DIR/remediate.yml" << 'EOF'
- hosts: all
  become: true
  gather_facts: true
  roles:
    - rhel9_observe
    - rhel9_remediate
EOF

cat > "$BASE_DIR/inventory" << 'EOF'
localhost ansible_connection=local
EOF

########################################
# README
########################################
cat > "$BASE_DIR/README.md" << 'EOF'
# Observability + Safe Remediation (RHEL9 Hardened)

## Step 1: Validate Environment

ansible --version
getenforce
fips-mode-setup --check

## Step 2: Syntax Check

ansible-playbook observe.yml -i inventory --syntax-check
ansible-playbook remediate.yml -i inventory --syntax-check

## Step 3: Run Observe

ansible-playbook observe.yml -i inventory

## Step 4: Review

Check:
- journalctl
- /var/tmp/fapolicyd_candidates.rules

## Step 5: Run Remediation (careful)

ansible-playbook remediate.yml -i inventory

## Notes

- No automatic trust applied
- No unsafe paths allowed
- Fully FIPS-safe
- Works on single node first
EOF

echo "[+] Done"
echo "Next:"
echo "cd observe"
echo "ansible-playbook observe.yml -i inventory --syntax-check"
