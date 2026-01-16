.PHONY: test test-unit test-e2e deps lint dev

# Run plugin in development mode
dev:
	nvim -u dev/init.lua

# Run all tests
test: deps
	nvim --headless -u tests/minimal_init.lua -c "lua require('mini.test').setup(); MiniTest.run()" -c "qa!"

# Run only unit tests
test-unit: deps
	nvim --headless -u tests/minimal_init.lua -c "lua require('mini.test').setup(); MiniTest.run_file('tests/unit')" -c "qa!"

# Run only e2e tests
test-e2e: deps
	nvim --headless -u tests/minimal_init.lua -c "lua require('mini.test').setup(); MiniTest.run_file('tests/e2e')" -c "qa!"

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
