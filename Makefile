.PHONY: test test-unit test-e2e test-e2e-sequential deps lint dev test-repo dev-repo setup-gh

# Run plugin in development mode
dev:
	nvim -u dev/init.lua

# Create a test repository for manual testing
test-repo:
	@./scripts/create-test-repo.sh

# Create test repo and open it with the plugin
dev-repo: test-repo
	cd /tmp/gitlad-test-repo && nvim -u $(CURDIR)/dev/init.lua

# Run all tests (unit sequential + e2e parallel)
test: test-unit test-e2e

# Run only unit tests
test-unit: deps
	nvim --headless -u tests/minimal_init.lua -c "lua require('mini.test').setup(); MiniTest.run({collect = {find_files = function() return vim.fn.glob('tests/unit/*.lua', false, true) end}})" -c "qa!"

# Run only e2e tests (parallel by default, requires GNU parallel)
# Use JOBS=N to control parallelism (default: 4)
test-e2e: deps
	@if command -v parallel > /dev/null; then \
		./scripts/run-tests-parallel.sh --e2e-only; \
	else \
		echo "GNU parallel not found, running sequentially..."; \
		$(MAKE) test-e2e-sequential; \
	fi

# Run e2e tests sequentially (useful for debugging)
test-e2e-sequential: deps
	nvim --headless -u tests/minimal_init.lua -c "lua require('mini.test').setup(); MiniTest.run({collect = {find_files = function() return vim.fn.glob('tests/e2e/*.lua', false, true) end}})" -c "qa!"

# Install test dependencies
deps:
	@echo "Checking for mini.nvim..."
	@if [ ! -d "$(HOME)/.local/share/nvim/site/pack/deps/start/mini.nvim" ]; then \
		echo "Installing mini.nvim..."; \
		mkdir -p $(HOME)/.local/share/nvim/site/pack/deps/start; \
		git clone --depth 1 https://github.com/echasnovski/mini.nvim \
			$(HOME)/.local/share/nvim/site/pack/deps/start/mini.nvim; \
	else \
		echo "mini.nvim already installed"; \
	fi

# Lint with stylua (if installed)
lint:
	@if command -v stylua > /dev/null; then \
		stylua --check lua/ tests/; \
	else \
		echo "stylua not installed, skipping lint"; \
	fi

# Format with stylua
format:
	@if command -v stylua > /dev/null; then \
		stylua lua/ tests/; \
	else \
		echo "stylua not installed"; \
	fi

# Clean test artifacts
clean:
	rm -rf .tests/

# Setup GitHub account for direnv
setup-gh:
	@if [ -f .envrc ]; then \
		echo ".envrc already exists. Remove it first if you want to reconfigure."; \
		exit 1; \
	fi
	@echo "Available GitHub accounts:"
	@gh auth status 2>&1 | grep "Logged in" | sed 's/.*account /  - /' | sed 's/ (.*//'
	@echo ""
	@read -p "Enter the GitHub account name to use for this project: " account; \
	if [ -z "$$account" ]; then \
		echo "Error: Account name cannot be empty"; \
		exit 1; \
	fi; \
	if ! gh auth token --user "$$account" > /dev/null 2>&1; then \
		echo "Error: Account '$$account' not found. Run 'gh auth login' first."; \
		exit 1; \
	fi; \
	echo "export GH_TOKEN=\$$(gh auth token --user $$account)" > .envrc; \
	echo "Created .envrc for account '$$account'"; \
	echo "Run 'direnv allow' to activate"
