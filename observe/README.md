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
