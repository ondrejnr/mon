# LAMP Stack na k3s + GCP

## Po klonovaní - 4 kroky:

# Závislosti
ansible-galaxy collection install -r requirements.yml

# SSH kľúč
cp ~/.ssh/gcp_key ./gcp_key && chmod 600 ./gcp_key

# Vault
echo "your-vault-password" > .vault_pass && chmod 600 .vault_pass
ansible-vault encrypt group_vars/vault.yml --vault-password-file .vault_pass

# DEPLOYMENT
ansible-playbook site.yml -i inventory/hosts.yml --vault-password-file .vault_pass
