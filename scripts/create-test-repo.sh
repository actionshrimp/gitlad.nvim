#!/usr/bin/env bash
# Creates a test git repository with realistic content for manual testing
set -e

REPO_DIR="${1:-/tmp/gitlad-test-repo}"

# Clean up existing repo
rm -rf "$REPO_DIR" "${REPO_DIR}-origin" "${REPO_DIR}-wt"
mkdir -p "$REPO_DIR"
cd "$REPO_DIR"

git init
git config user.email "test@example.com"
git config user.name "Test User"

# =============================================================================
# Commit 1: Initial project structure
# =============================================================================
mkdir -p src/components src/utils tests docs assets

cat > README.md << 'EOF'
# Test Project

A sample project for testing gitlad.nvim.

## Getting Started

```bash
npm install
npm run dev
```
EOF

cat > package.json << 'EOF'
{
  "name": "test-project",
  "version": "1.0.0",
  "scripts": {
    "dev": "node src/index.js",
    "test": "node tests/run.js"
  }
}
EOF

cat > src/index.js << 'EOF'
const { greet } = require('./utils/helpers');
const App = require('./components/App');

function main() {
  console.log(greet('World'));
  const app = new App();
  app.run();
}

main();
EOF

cat > src/utils/helpers.js << 'EOF'
function greet(name) {
  return `Hello, ${name}!`;
}

function formatDate(date) {
  return date.toISOString().split('T')[0];
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

module.exports = { greet, formatDate, sleep };
EOF

cat > src/components/App.js << 'EOF'
class App {
  constructor() {
    this.name = 'TestApp';
    this.version = '1.0.0';
  }

  run() {
    console.log(`Starting ${this.name} v${this.version}`);
    this.initialize();
  }

  initialize() {
    console.log('Initializing...');
  }
}

module.exports = App;
EOF

cat > tests/helpers.test.js << 'EOF'
const { greet, formatDate } = require('../src/utils/helpers');

function test(name, fn) {
  try {
    fn();
    console.log(`✓ ${name}`);
  } catch (e) {
    console.log(`✗ ${name}: ${e.message}`);
  }
}

test('greet returns greeting', () => {
  const result = greet('Test');
  if (result !== 'Hello, Test!') throw new Error('Unexpected result');
});

test('formatDate formats correctly', () => {
  const date = new Date('2024-01-15');
  const result = formatDate(date);
  if (result !== '2024-01-15') throw new Error('Unexpected result');
});
EOF

cat > .gitignore << 'EOF'
node_modules/
*.log
.DS_Store
dist/
coverage/
EOF

git add .
git commit -m "Initial project setup with basic structure"

# =============================================================================
# Commit 2: Add configuration and more utilities
# =============================================================================
cat > src/config.js << 'EOF'
const config = {
  appName: 'TestApp',
  version: '1.0.0',
  debug: process.env.DEBUG === 'true',
  api: {
    baseUrl: 'https://api.example.com',
    timeout: 5000,
  },
  features: {
    darkMode: true,
    notifications: true,
  },
};

module.exports = config;
EOF

cat > src/utils/logger.js << 'EOF'
const config = require('../config');

const levels = {
  DEBUG: 0,
  INFO: 1,
  WARN: 2,
  ERROR: 3,
};

function log(level, message, data = {}) {
  if (!config.debug && level === 'DEBUG') return;

  const timestamp = new Date().toISOString();
  const entry = { timestamp, level, message, ...data };
  console.log(JSON.stringify(entry));
}

module.exports = {
  debug: (msg, data) => log('DEBUG', msg, data),
  info: (msg, data) => log('INFO', msg, data),
  warn: (msg, data) => log('WARN', msg, data),
  error: (msg, data) => log('ERROR', msg, data),
};
EOF

cat > docs/API.md << 'EOF'
# API Documentation

## Endpoints

### GET /users
Returns a list of users.

### POST /users
Creates a new user.

### GET /users/:id
Returns a specific user.
EOF

git add .
git commit -m "Add configuration module and logger utility"

# =============================================================================
# Commit 3: Add components
# =============================================================================
cat > src/components/Button.js << 'EOF'
class Button {
  constructor(label, onClick) {
    this.label = label;
    this.onClick = onClick;
    this.disabled = false;
  }

  render() {
    return `<button ${this.disabled ? 'disabled' : ''}>${this.label}</button>`;
  }

  click() {
    if (!this.disabled && this.onClick) {
      this.onClick();
    }
  }
}

module.exports = Button;
EOF

cat > src/components/Input.js << 'EOF'
class Input {
  constructor(placeholder = '', type = 'text') {
    this.placeholder = placeholder;
    this.type = type;
    this.value = '';
  }

  render() {
    return `<input type="${this.type}" placeholder="${this.placeholder}" value="${this.value}" />`;
  }

  setValue(value) {
    this.value = value;
  }

  getValue() {
    return this.value;
  }
}

module.exports = Input;
EOF

cat > src/components/Modal.js << 'EOF'
class Modal {
  constructor(title, content) {
    this.title = title;
    this.content = content;
    this.isOpen = false;
  }

  open() {
    this.isOpen = true;
  }

  close() {
    this.isOpen = false;
  }

  render() {
    if (!this.isOpen) return '';
    return `
      <div class="modal">
        <div class="modal-header">${this.title}</div>
        <div class="modal-content">${this.content}</div>
      </div>
    `;
  }
}

module.exports = Modal;
EOF

git add .
git commit -m "Add UI components: Button, Input, Modal"

# =============================================================================
# Commit 4: Add binary files (images)
# =============================================================================
# Create a small valid PNG (1x1 red pixel)
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\xcf\xc0\x00\x00\x00\x03\x00\x01\x00\x05\xfe\xd4\x00\x00\x00\x00IEND\xaeB`\x82' > assets/logo.png

# Create a small valid GIF (1x1 blue pixel)
printf 'GIF89a\x01\x00\x01\x00\x80\x00\x00\x00\x00\xff\xff\xff\xff!\xf9\x04\x01\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;' > assets/icon.gif

# Create a binary data file
dd if=/dev/urandom of=assets/data.bin bs=256 count=1 2>/dev/null

git add .
git commit -m "Add binary assets: logo, icon, and data file"

# =============================================================================
# Commit 5: Add Python scripts
# =============================================================================
mkdir -p scripts

cat > scripts/analyze.py << 'EOF'
#!/usr/bin/env python3
"""Analyze project statistics."""

import os
import json
from pathlib import Path
from collections import defaultdict

def count_lines(filepath):
    """Count lines in a file."""
    try:
        with open(filepath, 'r') as f:
            return len(f.readlines())
    except:
        return 0

def analyze_project(root_dir):
    """Analyze the project directory."""
    stats = defaultdict(lambda: {'files': 0, 'lines': 0})

    for path in Path(root_dir).rglob('*'):
        if path.is_file() and not any(p.startswith('.') for p in path.parts):
            ext = path.suffix or 'no-ext'
            stats[ext]['files'] += 1
            stats[ext]['lines'] += count_lines(path)

    return dict(stats)

if __name__ == '__main__':
    results = analyze_project('.')
    print(json.dumps(results, indent=2))
EOF

cat > scripts/setup.py << 'EOF'
#!/usr/bin/env python3
"""Project setup script."""

import os
import subprocess

def run_command(cmd):
    """Run a shell command."""
    print(f"Running: {cmd}")
    subprocess.run(cmd, shell=True, check=True)

def setup():
    """Set up the project."""
    print("Setting up project...")

    # Install dependencies
    if os.path.exists('package.json'):
        run_command('npm install')

    # Create necessary directories
    os.makedirs('dist', exist_ok=True)
    os.makedirs('coverage', exist_ok=True)

    print("Setup complete!")

if __name__ == '__main__':
    setup()
EOF

chmod +x scripts/*.py

git add .
git commit -m "Add Python utility scripts"

# =============================================================================
# Commit 6: Add more tests
# =============================================================================
cat > tests/components.test.js << 'EOF'
const Button = require('../src/components/Button');
const Input = require('../src/components/Input');
const Modal = require('../src/components/Modal');

function test(name, fn) {
  try {
    fn();
    console.log(`✓ ${name}`);
  } catch (e) {
    console.log(`✗ ${name}: ${e.message}`);
  }
}

// Button tests
test('Button renders with label', () => {
  const btn = new Button('Click me');
  const html = btn.render();
  if (!html.includes('Click me')) throw new Error('Label not found');
});

test('Button can be disabled', () => {
  const btn = new Button('Submit');
  btn.disabled = true;
  const html = btn.render();
  if (!html.includes('disabled')) throw new Error('Disabled attribute not found');
});

// Input tests
test('Input renders with placeholder', () => {
  const input = new Input('Enter name');
  const html = input.render();
  if (!html.includes('Enter name')) throw new Error('Placeholder not found');
});

test('Input stores value', () => {
  const input = new Input();
  input.setValue('test value');
  if (input.getValue() !== 'test value') throw new Error('Value not stored');
});

// Modal tests
test('Modal is hidden by default', () => {
  const modal = new Modal('Title', 'Content');
  if (modal.render() !== '') throw new Error('Modal should be hidden');
});

test('Modal shows when opened', () => {
  const modal = new Modal('Title', 'Content');
  modal.open();
  const html = modal.render();
  if (!html.includes('Title')) throw new Error('Modal not visible');
});
EOF

cat > tests/run.js << 'EOF'
#!/usr/bin/env node
const path = require('path');
const fs = require('fs');

const testDir = __dirname;
const testFiles = fs.readdirSync(testDir)
  .filter(f => f.endsWith('.test.js'));

console.log(`Running ${testFiles.length} test files...\n`);

testFiles.forEach(file => {
  console.log(`\n=== ${file} ===`);
  require(path.join(testDir, file));
});

console.log('\nDone!');
EOF

git add .
git commit -m "Add component tests and test runner"

# =============================================================================
# Commit 7: Add a submodule
# =============================================================================
LIB_DIR="/tmp/gitlad-test-lib"

# Create the library repo first
rm -rf "$LIB_DIR"
mkdir -p "$LIB_DIR"
git -C "$LIB_DIR" init
git -C "$LIB_DIR" config user.email "test@example.com"
git -C "$LIB_DIR" config user.name "Test User"

cat > "$LIB_DIR/index.js" << 'EOF'
// Shared library utilities
function add(a, b) {
  return a + b;
}

function subtract(a, b) {
  return a - b;
}

function multiply(a, b) {
  return a * b;
}

module.exports = { add, subtract, multiply };
EOF

cat > "$LIB_DIR/README.md" << 'EOF'
# Shared Library

Common utilities shared across projects.

## Usage

```js
const { add, subtract, multiply } = require('./lib');
```
EOF

git -C "$LIB_DIR" add .
git -C "$LIB_DIR" commit -m "Initial library with math utilities"

# Add a second commit to the library
cat >> "$LIB_DIR/index.js" << 'EOF'

function divide(a, b) {
  if (b === 0) throw new Error('Division by zero');
  return a / b;
}

module.exports.divide = divide;
EOF

git -C "$LIB_DIR" add .
git -C "$LIB_DIR" commit -m "Add divide function"

# Add the library as a submodule to the main repo
# Use -c protocol.file.allow=always to allow file:// protocol (Git security feature)
git -c protocol.file.allow=always submodule add "$LIB_DIR" lib
git commit -m "Add shared library as submodule"

# =============================================================================
# Now create working copy changes (staged and unstaged)
# =============================================================================

# --- Staged changes ---

# Modified file (staged)
cat > src/config.js << 'EOF'
const config = {
  appName: 'TestApp',
  version: '1.1.0',  // Updated version
  debug: process.env.DEBUG === 'true',
  api: {
    baseUrl: process.env.API_URL || 'https://api.example.com',
    timeout: 5000,
    retries: 3,  // New option
  },
  features: {
    darkMode: true,
    notifications: true,
    analytics: false,  // New feature flag
  },
};

module.exports = config;
EOF
git add src/config.js

# New file (staged)
cat > src/utils/validator.js << 'EOF'
function isEmail(str) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(str);
}

function isURL(str) {
  try {
    new URL(str);
    return true;
  } catch {
    return false;
  }
}

function isNotEmpty(str) {
  return str && str.trim().length > 0;
}

module.exports = { isEmail, isURL, isNotEmpty };
EOF
git add src/utils/validator.js

# Another new file (staged)
cat > src/components/Card.js << 'EOF'
class Card {
  constructor(title, body, footer = null) {
    this.title = title;
    this.body = body;
    this.footer = footer;
  }

  render() {
    return `
      <div class="card">
        <div class="card-title">${this.title}</div>
        <div class="card-body">${this.body}</div>
        ${this.footer ? `<div class="card-footer">${this.footer}</div>` : ''}
      </div>
    `;
  }
}

module.exports = Card;
EOF
git add src/components/Card.js

# --- Unstaged changes ---

# Modified file (unstaged)
cat > src/utils/helpers.js << 'EOF'
function greet(name) {
  return `Hello, ${name}!`;
}

function formatDate(date) {
  return date.toISOString().split('T')[0];
}

function formatDateTime(date) {
  return date.toISOString().replace('T', ' ').slice(0, 19);
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function debounce(fn, delay) {
  let timeout;
  return (...args) => {
    clearTimeout(timeout);
    timeout = setTimeout(() => fn(...args), delay);
  };
}

module.exports = { greet, formatDate, formatDateTime, sleep, debounce };
EOF

# Another modified file (unstaged)
cat > README.md << 'EOF'
# Test Project

A sample project for testing gitlad.nvim.

## Features

- Component-based architecture
- Utility functions
- Comprehensive tests

## Getting Started

```bash
npm install
npm run dev
```

## Testing

```bash
npm test
```

## License

MIT
EOF

# Modified component (unstaged)
cat > src/components/Button.js << 'EOF'
class Button {
  constructor(label, onClick) {
    this.label = label;
    this.onClick = onClick;
    this.disabled = false;
    this.loading = false;
  }

  render() {
    const attrs = [];
    if (this.disabled || this.loading) attrs.push('disabled');
    if (this.loading) attrs.push('data-loading');

    const label = this.loading ? 'Loading...' : this.label;
    return `<button ${attrs.join(' ')}>${label}</button>`;
  }

  click() {
    if (!this.disabled && !this.loading && this.onClick) {
      this.onClick();
    }
  }

  setLoading(loading) {
    this.loading = loading;
  }
}

module.exports = Button;
EOF

# --- Untracked files ---

cat > src/utils/cache.js << 'EOF'
class Cache {
  constructor(ttl = 60000) {
    this.store = new Map();
    this.ttl = ttl;
  }

  set(key, value) {
    this.store.set(key, {
      value,
      expires: Date.now() + this.ttl,
    });
  }

  get(key) {
    const entry = this.store.get(key);
    if (!entry) return null;
    if (Date.now() > entry.expires) {
      this.store.delete(key);
      return null;
    }
    return entry.value;
  }

  clear() {
    this.store.clear();
  }
}

module.exports = Cache;
EOF

cat > notes.txt << 'EOF'
TODO:
- Add authentication module
- Implement rate limiting
- Write more tests
- Update documentation
EOF

cat > src/components/Dropdown.js << 'EOF'
class Dropdown {
  constructor(options = []) {
    this.options = options;
    this.selected = null;
    this.isOpen = false;
  }

  toggle() {
    this.isOpen = !this.isOpen;
  }

  select(value) {
    this.selected = value;
    this.isOpen = false;
  }

  render() {
    const optionsHtml = this.options
      .map(opt => `<li data-value="${opt.value}">${opt.label}</li>`)
      .join('');

    return `
      <div class="dropdown ${this.isOpen ? 'open' : ''}">
        <button class="dropdown-toggle">${this.selected || 'Select...'}</button>
        <ul class="dropdown-menu">${optionsHtml}</ul>
      </div>
    `;
  }
}

module.exports = Dropdown;
EOF

# Create an untracked binary file
dd if=/dev/urandom of=assets/new-image.bin bs=128 count=1 2>/dev/null

# --- Modified submodule (unstaged) ---
# Add a new commit to the library and update the submodule to it
# This makes the submodule appear in "Unstaged changes" with new commits

cat >> "$LIB_DIR/index.js" << 'EOF'

function modulo(a, b) {
  return a % b;
}

module.exports.modulo = modulo;
EOF

git -C "$LIB_DIR" add .
git -C "$LIB_DIR" commit -m "Add modulo function"

# Update submodule to the new commit (this creates an unstaged change)
git -C lib fetch
git -C lib checkout origin/HEAD 2>/dev/null || git -C lib pull

# =============================================================================
# Create branches for merge testing
# =============================================================================

# Create a clean-merge branch (can be fast-forwarded or merged cleanly)
git stash -q  # Stash current changes temporarily
git checkout -b feature/clean-merge
cat > src/utils/math.js << 'EOF'
function add(a, b) {
  return a + b;
}

function subtract(a, b) {
  return a - b;
}

function multiply(a, b) {
  return a * b;
}

function divide(a, b) {
  if (b === 0) throw new Error('Division by zero');
  return a / b;
}

module.exports = { add, subtract, multiply, divide };
EOF
git add src/utils/math.js
git commit -m "Add math utility functions"

# Create a conflict-merge branch (will conflict with main)
git checkout main
git checkout -b feature/conflict-merge

cat > src/components/App.js << 'EOF'
class App {
  constructor() {
    this.name = 'ConflictApp';  // This will conflict
    this.version = '2.0.0';
  }

  run() {
    console.log(`Running ${this.name} v${this.version}`);
    this.initialize();
  }

  initialize() {
    console.log('Conflict branch initialization...');
  }
}

module.exports = App;
EOF
git add src/components/App.js
git commit -m "Update App component (will conflict)"

# Go back to main and modify App.js to create conflict scenario
git checkout main

cat > src/components/App.js << 'EOF'
class App {
  constructor() {
    this.name = 'MainApp';  // This will conflict with feature/conflict-merge
    this.version = '1.5.0';
  }

  run() {
    console.log(`Starting ${this.name} v${this.version}`);
    this.initialize();
  }

  initialize() {
    console.log('Main branch initialization...');
  }
}

module.exports = App;
EOF
git add src/components/App.js
git commit -m "Update App component on main"

# =============================================================================
# Set up a remote so status shows origin/main tracking
# =============================================================================
git clone --bare "$REPO_DIR" "${REPO_DIR}-origin" 2>/dev/null
git remote add origin "${REPO_DIR}-origin"
git fetch origin 2>/dev/null
git branch --set-upstream-to=origin/main main

# Add 3 more commits on main (these will be "unpushed" / ahead of origin)
cat > src/utils/format.js << 'EOF'
function capitalize(str) {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

function truncate(str, maxLen = 50) {
  if (str.length <= maxLen) return str;
  return str.slice(0, maxLen - 3) + '...';
}

function padLeft(str, len, char = ' ') {
  return String(str).padStart(len, char);
}

module.exports = { capitalize, truncate, padLeft };
EOF
git add src/utils/format.js
git commit -m "Add string formatting utilities"

mkdir -p src/middleware
cat > src/middleware/auth.js << 'EOF'
function authenticate(req) {
  const token = req.headers['authorization'];
  if (!token) return { authenticated: false, error: 'No token provided' };

  try {
    const decoded = decodeToken(token.replace('Bearer ', ''));
    return { authenticated: true, user: decoded };
  } catch (e) {
    return { authenticated: false, error: 'Invalid token' };
  }
}

function decodeToken(token) {
  // Simplified token decode for demo
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('Malformed token');
  return JSON.parse(Buffer.from(parts[1], 'base64').toString());
}

module.exports = { authenticate, decodeToken };
EOF
git add src/middleware/auth.js
git commit -m "Add authentication middleware"

cat > src/index.js << 'EOF'
const { greet } = require('./utils/helpers');
const { capitalize } = require('./utils/format');
const { authenticate } = require('./middleware/auth');
const App = require('./components/App');

function main() {
  console.log(greet(capitalize('world')));
  const app = new App();
  app.run();
}

main();
EOF
git add src/index.js
git commit -m "Wire up auth middleware and formatters"

git stash pop -q 2>/dev/null || true  # Restore stashed changes

# --- Staged rename (added after stash pop to preserve index state) ---
git mv docs/API.md docs/API-REFERENCE.md
cat > docs/API-REFERENCE.md << 'EOF'
# API Reference

## Endpoints

### GET /users
Returns a list of users.

### POST /users
Creates a new user.

### GET /users/:id
Returns a specific user.

### DELETE /users/:id
Deletes a specific user.
EOF
git add docs/API-REFERENCE.md

# =============================================================================
# Add a pre-commit hook that simulates a slow linting process
# =============================================================================
cat > .git/hooks/pre-commit << 'HOOK'
#!/usr/bin/env bash
echo "Running pre-commit checks..."
for i in {1..10}; do
  sleep 0.1
  echo "Checking step $i/10..."
done

# Fail if FAIL_HOOK file is staged
if git diff --cached --name-only | grep -q "^FAIL_HOOK$"; then
  echo ""
  echo "ERROR: FAIL_HOOK file detected in commit!"
  echo "This simulates a linting failure."
  exit 1
fi

echo "All checks passed!"
exit 0
HOOK
chmod +x .git/hooks/pre-commit

# =============================================================================
# Create worktrees (need min_count=2 to show in status)
# =============================================================================
WORKTREE_DIR="${REPO_DIR}-wt"
mkdir -p "$WORKTREE_DIR"
git worktree add "$WORKTREE_DIR/hotfix" -b hotfix HEAD~2
git worktree add "$WORKTREE_DIR/experiment" -b experiment HEAD~4

echo ""
echo "=========================================="
echo "Test repository created at: $REPO_DIR"
echo "=========================================="
echo ""
echo "Status:"
git status --short
echo ""
echo "Remote tracking:"
echo "  origin → ${REPO_DIR}-origin"
echo "  Unpushed commits: $(git rev-list --count origin/main..HEAD)"
echo ""
echo "Worktrees:"
git worktree list
echo ""
echo "Submodule status:"
git submodule status
echo ""
echo "Branches for merge testing:"
echo "  - feature/clean-merge: Can be merged cleanly (adds math.js)"
echo "  - feature/conflict-merge: Will conflict with main (both modified App.js)"
echo ""
echo "Staged section includes a renamed file: docs/{API.md => API-REFERENCE.md}"
echo "The 'lib' submodule has new commits - it will appear in Unstaged changes."
echo "Use this to test submodule popup context from file entries."
echo ""
echo "Pre-commit hook installed:"
echo "  - Runs 10 iterations with 100ms delay each"
echo "  - Fails if 'FAIL_HOOK' file is staged (touch FAIL_HOOK && git add FAIL_HOOK)"
echo "  - Use this to test the commit output viewer"
echo ""
echo "To use with gitlad.nvim:"
echo "  cd $REPO_DIR && nvim -u $(dirname "$0")/../dev/init.lua"
