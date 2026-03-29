# Jarvis Usage Examples

## Getting Started

```bash
# From anywhere, point to your project
./jarvis.sh /path/to/your/project

# Or from your project directory
cd /path/to/your/project
/path/to/jarvis-coding/jarvis.sh
```

## Voice Commands Examples

### Creating Code
- 🗣️ **"Claude create a Next.js API route for user authentication"**
- 🗣️ **"Create a React component for displaying user profiles"**
- 🗣️ **"Write a Python function that validates email addresses"**
- 🗣️ **"Add a new REST endpoint for updating settings"**

### Refactoring
- 🗣️ **"Claude refactor the login function to use async await"**
- 🗣️ **"Refactor this class to use dependency injection"**
- 🗣️ **"Extract the validation logic into a separate module"**
- 🗣️ **"Simplify the error handling in the API layer"**

### Bug Fixes
- 🗣️ **"Fix the authentication bug in the middleware"**
- 🗣️ **"Debug why the API is returning 500 errors"**
- 🗣️ **"Fix the memory leak in the socket connection"**
- 🗣️ **"Resolve the race condition in the cache layer"**

### Testing
- 🗣️ **"Write unit tests for the authentication service"**
- 🗣️ **"Add integration tests for the API endpoints"**
- 🗣️ **"Create test cases for edge cases in validation"**
- 🗣️ **"Run the test suite and fix any failures"**

### Code Review & Analysis
- 🗣️ **"Review the security of the authentication code"**
- 🗣️ **"Analyze the performance of the database queries"**
- 🗣️ **"Check for potential bugs in the payment processing"**
- 🗣️ **"Suggest improvements for the error handling"**

### Documentation
- 🗣️ **"Add JSDoc comments to the API functions"**
- 🗣️ **"Document the authentication flow"**
- 🗣️ **"Create a README for the API module"**

## Pro Tips

### Be Specific
❌ "Claude fix this"
✅ "Claude fix the null pointer error in the user service"

### Include Context
❌ "Add validation"
✅ "Add email validation to the registration form"

### Natural Language Works
You don't need to be super formal. Jarvis understands:
- "Make this function async"
- "Can you add error handling here?"
- "This is broken, please fix it"

### Multi-Step Commands
You can chain requests:
- 🗣️ **"Create a user model, add validation, and write tests"**
- 🗣️ **"Refactor the API layer and update the documentation"**

## Keyboard Shortcuts

- **HOLD SPACE** - Record voice input
- **RELEASE SPACE** - Process and execute
- **ESC** - Quit Jarvis

## Working with Files

Jarvis operates in the context of your working directory:

```bash
# Option 1: Navigate first
cd ~/my-project
/path/to/jarvis.sh

# Option 2: Pass directory
/path/to/jarvis.sh ~/my-project
```

All Claude Code commands will execute in that directory.

## Advanced Usage

### Using with Git Workflows
```bash
# Start in feature branch
git checkout -b feature/voice-auth
./jarvis.sh

# 🗣️ "Claude implement OAuth authentication"
# 🗣️ "Add tests for the OAuth flow"
# 🗣️ "Create a pull request with these changes"
```

### Debugging Session
```bash
./jarvis.sh

# 🗣️ "Show me the error logs"
# 🗣️ "Find where the null pointer exception is happening"
# 🗣️ "Fix the bug and run the tests"
```

### Rapid Prototyping
```bash
./jarvis.sh

# 🗣️ "Create a new Express server with TypeScript"
# 🗣️ "Add a REST API for todos"
# 🗣️ "Add database persistence with Postgres"
# 🗣️ "Deploy to Docker"
```

## What Makes Jarvis Powerful

Unlike simple voice-to-text tools:
- ✅ **Context aware** - Understands your codebase
- ✅ **Executes automatically** - No copy/paste needed
- ✅ **Full Claude capabilities** - Not just dictation
- ✅ **Project-scoped** - Works in any directory
- ✅ **Privacy-first** - Local speech recognition

## Limitations

- Requires clear audio input
- Works best with technical English
- Claude Code CLI must be installed and authenticated
- Needs microphone permissions granted

## Next Steps

Try it out:
```bash
./jarvis.sh
```

Hold SPACE and say: **"Claude create a hello world function"**
