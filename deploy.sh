#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(pwd)/compliance"
ROLE_DIR="$BASE_DIR/roles/rhel9_compliance/tasks"
VARS_DIR="$BASE_DIR/roles/rhel9_compliance/vars"

echo "[+] Creating directory structure"
mkdir -p "$ROLE_DIR" "$VARS_DIR"

echo "[+] Writing vars/main.yml"
cat > "$VARS_DIR/main.yml" << 'EOF'
---
approved_crypto_policy: "FIPS"
required_services:
  - fapolicyd
  - auditd
secure_umask: "027"
EOF

echo "[+] Writing tasks/main.yml"
cat > "$ROLE_DIR/main.yml" << 'EOF'
---
- import_tasks: precheck.yml
- import_tasks: fips.yml
- import_tasks: fapolicyd.yml
- import_tasks: selinux.yml
- import_tasks: crypto.yml
- import_tasks: audit.yml
EOF

echo "[+] Writing tasks/precheck.yml"
cat > "$ROLE_DIR/precheck.yml" << 'EOF'
---
- name: Gather service facts
  ansible.builtin.service_facts:

- name: Gather package facts
  ansible.builtin.package_facts:
EOF

echo "[+] Writing tasks/fips.yml"
cat > "$ROLE_DIR/fips.yml" << 'EOF'
---
- name: Read kernel FIPS flag
  ansible.builtin.slurp:
    src: /proc/sys/crypto/fips_enabled
  register: fips_state

- name: Assert FIPS enabled
  ansible.builtin.assert:
    that:
      - (fips_state.content | b64decode | trim) == '1'
EOF

echo "[+] Writing tasks/fapolicyd.yml"
cat > "$ROLE_DIR/fapolicyd.yml" << 'EOF'
---
- name: Verify fapolicyd installed
  ansible.builtin.assert:
    that:
      - "'fapolicyd' in ansible_facts.packages"

- name: Verify fapolicyd running
  ansible.builtin.assert:
    that:
      - ansible_facts.services['fapolicyd.service'].state == 'running'
EOF

echo "[+] Writing tasks/selinux.yml"
cat > "$ROLE_DIR/selinux.yml" << 'EOF'
---
- name: Get SELinux mode
  ansible.builtin.command: getenforce
  register: selinux_mode
  changed_when: false

- name: Assert enforcing
  ansible.builtin.assert:
    that:
      - selinux_mode.stdout == "Enforcing"
EOF

echo "[+] Writing tasks/crypto.yml"
cat > "$ROLE_DIR/crypto.yml" << 'EOF'
---
- name: Check crypto policy
  ansible.builtin.command: update-crypto-policies --show
  register: crypto_policy
  changed_when: false

- name: Assert FIPS policy
  ansible.builtin.assert:
    that:
      - crypto_policy.stdout == "FIPS"
EOF

echo "[+] Writing tasks/audit.yml"
cat > "$ROLE_DIR/audit.yml" << 'EOF'
---
- name: Verify auditd running
  ansible.builtin.assert:
    that:
      - ansible_facts.services['auditd.service'].state == 'running'
EOF

echo "[+] Writing monitor.yml"
cat > "$BASE_DIR/monitor.yml" << 'EOF'
---
- name: Continuous Compliance Monitoring
  hosts: localhost
  become: true
  connection: local

  tasks:
    - name: Run compliance role
      include_role:
        name: rhel9_compliance
      check_mode: true
EOF

echo "[+] Writing inventory"
cat > "$BASE_DIR/inventory" << 'EOF'
localhost ansible_connection=local
EOF

echo "[+] Deployment complete"
echo "Run: ansible-playbook monitor.yml -i inventory"#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(pwd)/compliance"
ROLE_DIR="$BASE_DIR/roles/rhel9_compliance/tasks"
VARS_DIR="$BASE_DIR/roles/rhel9_compliance/vars"

echo "[+] Creating directory structure"
mkdir -p "$ROLE_DIR" "$VARS_DIR"

echo "[+] Writing vars/main.yml"
cat > "$VARS_DIR/main.yml" << 'EOF'
---
approved_crypto_policy: "FIPS"
required_services:
  - fapolicyd
  - auditd
secure_umask: "027"
EOF

echo "[+] Writing tasks/main.yml"
cat > "$ROLE_DIR/main.yml" << 'EOF'
---
- import_tasks: precheck.yml
- import_tasks: fips.yml
- import_tasks: fapolicyd.yml
- import_tasks: selinux.yml
- import_tasks: crypto.yml
- import_tasks: audit.yml
EOF

echo "[+] Writing tasks/precheck.yml"
cat > "$ROLE_DIR/precheck.yml" << 'EOF'
---
- name: Gather service facts
  ansible.builtin.service_facts:

- name: Gather package facts
  ansible.builtin.package_facts:
EOF

echo "[+] Writing tasks/fips.yml"
cat > "$ROLE_DIR/fips.yml" << 'EOF'
---
- name: Read kernel FIPS flag
  ansible.builtin.slurp:
    src: /proc/sys/crypto/fips_enabled
  register: fips_state

- name: Assert FIPS enabled
  ansible.builtin.assert:
    that:
      - (fips_state.content | b64decode | trim) == '1'
EOF

echo "[+] Writing tasks/fapolicyd.yml"
cat > "$ROLE_DIR/fapolicyd.yml" << 'EOF'
---
- name: Verify fapolicyd installed
  ansible.builtin.assert:
    that:
      - "'fapolicyd' in ansible_facts.packages"

- name: Verify fapolicyd running
  ansible.builtin.assert:
    that:
      - ansible_facts.services['fapolicyd.service'].state == 'running'
EOF

echo "[+] Writing tasks/selinux.yml"
cat > "$ROLE_DIR/selinux.yml" << 'EOF'
---
- name: Get SELinux mode
  ansible.builtin.command: getenforce
  register: selinux_mode
  changed_when: false

- name: Assert enforcing
  ansible.builtin.assert:
    that:
      - selinux_mode.stdout == "Enforcing"
EOF

echo "[+] Writing tasks/crypto.yml"
cat > "$ROLE_DIR/crypto.yml" << 'EOF'
---
- name: Check crypto policy
  ansible.builtin.command: update-crypto-policies --show
  register: crypto_policy
  changed_when: false

- name: Assert FIPS policy
  ansible.builtin.assert:
    that:
      - crypto_policy.stdout == "FIPS"
EOF

echo "[+] Writing tasks/audit.yml"
cat > "$ROLE_DIR/audit.yml" << 'EOF'
---
- name: Verify auditd running
  ansible.builtin.assert:
    that:
      - ansible_facts.services['auditd.service'].state == 'running'
EOF

echo "[+] Writing monitor.yml"
cat > "$BASE_DIR/monitor.yml" << 'EOF'
---
- name: Continuous Compliance Monitoring
  hosts: localhost
  become: true
  connection: local

  tasks:
    - name: Run compliance role
      include_role:
        name: rhel9_compliance
      check_mode: true
EOF

echo "[+] Writing inventory"
cat > "$BASE_DIR/inventory" << 'EOF'
localhost ansible_connection=local
EOF

echo "[+] Deployment complete"
echo "Run: ansible-playbook monitor.yml -i inventory"
