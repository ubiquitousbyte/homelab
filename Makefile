.PHONY: help
help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-24s %s\n", $$1, $$2}'

.PHONY: site
site: ## Run the full Ansible playbook
	ansible-playbook playbooks/site.yml

.PHONY: nomad-restart-server
nomad-restart-server: ## Restart Nomad on server nodes
	ansible nomad_server -a "systemctl restart nomad"

.PHONY: nomad-restart-client
nomad-restart-client: ## Restart Nomad on client nodes
	ansible nomad_client -a "systemctl restart nomad"

.PHONY: nomad-restart
nomad-restart: ## Restart Nomad on all nodes (server first, then clients)
	ansible nomad_server -a "systemctl restart nomad"
	ansible nomad_client -a "systemctl restart nomad"

.PHONY: nomad-status
nomad-status: ## Show Nomad service status on all nodes
	ansible nomad -a "systemctl status nomad"
