# /commit Command Documentation

**Purpose:** Generate and execute a semantic commit message following conventional commit standards.

**Usage:** `/commit`

**AI Workflow:**
1. **Analyze changes**: Read git diff and understand the scope of changes
2. **Determine type**: Choose from feat, fix, docs, style, refactor, test, chore
3. **Generate scope**: Identify affected component/area
4. **Write description**: Clear, concise summary of changes
5. **Add body if needed**: For breaking changes or detailed explanations

**Conventional Commit Format:**
```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style/formatting
- `refactor`: Code restructuring
- `test`: Test additions/modifications
- `chore`: Maintenance tasks

**Examples:**
- `feat(auth): add user login validation`
- `fix(api): resolve null pointer in user service`
- `docs(readme): update installation instructions`
- `refactor(db): optimize query performance`

**Features:**
- ✅ Auto-stages all changes if none are staged
- ✅ Generates semantic commit message
- ✅ Follows conventional commit standards
- ✅ Includes scope identification
- ✅ Handles breaking changes appropriately

**Manual override:**
If AI-generated message needs adjustment, modify before committing:
```bash
git commit --amend  # Then edit the message
```