# HTMX Widgets: Custom Form Components

Advanced form widgets that integrate HTMX with Alpine.js for enhanced user experience. These widgets provide rich interactions while maintaining server-side rendering and validation.

## Autocomplete Widget

**Django widget for server-side search with client-side UX:**

```python
# widgets.py
from django import forms

class AutocompleteWidget(forms.Select):
    template_name = 'widgets/autocomplete.html'
    
    def __init__(self, url, min_chars=2, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.url = url
        self.min_chars = min_chars
    
    def get_context(self, name, value, attrs):
        context = super().get_context(name, value, attrs)
        context['widget']['url'] = self.url
        context['widget']['min_chars'] = self.min_chars
        return context
```

**Widget template** (`widgets/autocomplete.html`):

```django
<div class="autocomplete-container">
    <input type="text" 
           class="input autocomplete-input" 
           placeholder="Type to search..."
           hx-get="{{ widget.url }}"
           hx-trigger="keyup changed delay:300ms"
           hx-target="[data-autocomplete-results='{{ widget.attrs.id }}']"
           data-min-chars="{{ widget.min_chars }}">
    
    <input type="hidden" name="{{ widget.name }}" value="{{ widget.value|default:'' }}">
    
    <div class="autocomplete-results" 
         data-autocomplete-results="{{ widget.attrs.id }}" 
         style="display: none;">
        <!-- Results loaded here via HTMX -->
    </div>
</div>
```

**Autocomplete JavaScript** (`autocomplete.js`):

```javascript
/**
 * Select an autocomplete item
 */
function selectAutocompleteItem(element, value, text) {
    const container = element.closest('.autocomplete-container');
    if (!container) return;
    
    // Update visible input
    const displayInput = container.querySelector('.autocomplete-input');
    if (displayInput) displayInput.value = text;
    
    // Update hidden input
    const hiddenInput = container.querySelector('input[type="hidden"]');
    if (hiddenInput) hiddenInput.value = value;
    
    // Hide results
    const results = container.querySelector('.autocomplete-results');
    if (results) results.style.display = 'none';
}

// Handle HTMX requests - add query parameter
document.addEventListener('htmx:configRequest', function(event) {
    const input = event.detail.elt;
    if (input && input.classList.contains('autocomplete-input')) {
        const minChars = parseInt(input.dataset.minChars || '2');
        const currentValue = input.value || '';
        
        // Cancel if too short
        if (currentValue.length < minChars) {
            event.preventDefault();
            return false;
        }
        
        // Add query parameter
        event.detail.parameters = { q: currentValue };
    }
});

// Show/hide results after HTMX swap
document.addEventListener('htmx:afterSwap', function(event) {
    const target = event.detail.target;
    if (target && target.hasAttribute('data-autocomplete-results')) {
        const items = target.querySelectorAll('.autocomplete-item');
        target.style.display = items.length > 0 ? 'block' : 'none';
    }
});

// Keyboard navigation (Arrow Up/Down, Enter, Escape)
document.addEventListener('keydown', function(event) {
    const input = event.target;
    if (!input || !input.classList.contains('autocomplete-input')) return;
    
    const container = input.closest('.autocomplete-container');
    if (!container) return;
    
    const results = container.querySelector('.autocomplete-results');
    if (!results || results.style.display === 'none') return;
    
    const items = Array.from(results.querySelectorAll('.autocomplete-item:not(.disabled)'));
    if (items.length === 0) return;
    
    let currentIndex = items.findIndex(item => item.classList.contains('is-active'));
    
    if (event.key === 'ArrowDown') {
        event.preventDefault();
        items.forEach(item => item.classList.remove('is-active'));
        currentIndex = (currentIndex + 1) % items.length;
        items[currentIndex].classList.add('is-active');
        items[currentIndex].scrollIntoView({ block: 'nearest' });
    } else if (event.key === 'ArrowUp') {
        event.preventDefault();
        items.forEach(item => item.classList.remove('is-active'));
        currentIndex = currentIndex <= 0 ? items.length - 1 : currentIndex - 1;
        items[currentIndex].classList.add('is-active');
        items[currentIndex].scrollIntoView({ block: 'nearest' });
    } else if (event.key === 'Enter') {
        event.preventDefault();
        const activeItem = items.find(item => item.classList.contains('is-active'));
        if (activeItem) {
            const value = activeItem.dataset.value;
            const text = activeItem.dataset.text || activeItem.textContent.trim();
            selectAutocompleteItem(activeItem, value, text);
        }
    } else if (event.key === 'Escape') {
        event.preventDefault();
        results.style.display = 'none';
    }
});
```

## File Upload with Drag & Drop

**Alpine.js component for multi-file uploads with progress tracking:**

```javascript
function attachmentUpload() {
    return {
        dragging: false,
        uploading: false,
        uploadProgress: 0,
        selectedFiles: [],
        errorMessage: '',
        
        handleFileSelect(event) {
            const files = Array.from(event.target.files || []);
            if (files.length === 0) return;
            
            const validationResult = this.validateFiles(files);
            if (!validationResult.valid) {
                this.errorMessage = validationResult.error;
                event.target.value = '';
                return;
            }
            
            this.selectedFiles.push(...files);
            this.errorMessage = '';
            event.target.value = '';
        },
        
        handleDrop(event) {
            this.dragging = false;
            const files = Array.from(event.dataTransfer.files || []);
            if (files.length === 0) return;
            
            const validationResult = this.validateFiles(files);
            if (!validationResult.valid) {
                this.errorMessage = validationResult.error;
                return;
            }
            
            this.selectedFiles.push(...files);
            this.errorMessage = '';
        },
        
        validateFiles(files) {
            const maxSize = 10 * 1024 * 1024; // 10MB
            const allowedTypes = ['image/jpeg', 'image/png', 'application/pdf'];
            
            for (const file of files) {
                if (file.size > maxSize) {
                    return {
                        valid: false,
                        error: `File "${file.name}" exceeds 10MB limit.`
                    };
                }
                
                if (!allowedTypes.includes(file.type)) {
                    return {
                        valid: false,
                        error: `File "${file.name}" has unsupported type.`
                    };
                }
            }
            
            return { valid: true };
        },
        
        removeFile(index) {
            this.selectedFiles.splice(index, 1);
        },
        
        async handleSubmit(event) {
            event.preventDefault();
            
            if (this.selectedFiles.length === 0) {
                this.errorMessage = 'Please select at least one file.';
                return;
            }
            
            this.uploading = true;
            this.uploadProgress = 0;
            
            const form = event.target;
            const formData = new FormData(form);
            
            for (let i = 0; i < this.selectedFiles.length; i++) {
                const file = this.selectedFiles[i];
                const fileFormData = new FormData();
                
                // Copy hidden fields
                for (const [key, value] of formData.entries()) {
                    if (key !== 'file') {
                        fileFormData.append(key, value);
                    }
                }
                
                fileFormData.append('file', file);
                
                this.uploadProgress = Math.round(((i + 1) / this.selectedFiles.length) * 100);
                
                try {
                    const response = await fetch(form.action, {
                        method: 'POST',
                        body: fileFormData,
                        headers: {
                            'X-CSRFToken': formData.get('csrfmiddlewaretoken'),
                            'HX-Request': 'true'
                        }
                    });
                    
                    if (!response.ok) {
                        throw new Error('Upload failed');
                    }
                 } catch (error) {
                     this.uploading = false;
                     this.errorMessage = `Error uploading ${file.name}: ${error.message}`;
                     // Clear all files on any failure to prevent partial duplicates on retry
                     this.selectedFiles = [];
                     return;
                 }
            }
            
            // All files uploaded successfully
            this.uploading = false;
            this.uploadProgress = 0;
            this.selectedFiles = [];
            
            // Refresh attachments section
            if (window.htmx) {
                htmx.ajax('GET', window.location.href + '?section=attachments', {
                    target: '#attachments-section',
                    swap: 'outerHTML'
                });
            }
        },
        
        formatFileSize(bytes) {
            if (bytes === 0) return '0 Bytes';
            const k = 1024;
            const sizes = ['Bytes', 'KB', 'MB', 'GB'];
            const i = Math.floor(Math.log(bytes) / Math.log(k));
            return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i];
        }
    };
}
```

**Template usage:**

```django
<div x-data="attachmentUpload()" class="attachment-upload-zone">
    <form @submit="handleSubmit" id="attachment-upload-form">
        {% csrf_token %}
        
        <!-- Drag & Drop Zone -->
        <div class="file-drop-zone" 
             @dragover.prevent="dragging = true"
             @dragleave.prevent="dragging = false"
             @drop.prevent="handleDrop"
             :class="{ 'is-active': dragging }">
            <p>Drag files here or click to select</p>
            <input type="file" 
                   multiple 
                   @change="handleFileSelect" 
                   style="display: none;" 
                   id="file-input">
            <button type="button" 
                    class="button is-primary" 
                    @click="$el.previousElementSibling.click()">
                Select Files
            </button>
        </div>
        
        <!-- Selected Files List -->
        <div x-show="selectedFiles.length > 0" class="selected-files">
            <template x-for="(file, index) in selectedFiles" :key="index">
                <div class="file-item">
                    <span x-text="file.name"></span>
                    <span x-text="formatFileSize(file.size)"></span>
                    <button type="button" 
                            @click="removeFile(index)" 
                            class="delete"></button>
                </div>
            </template>
        </div>
        
        <!-- Error Message -->
        <div x-show="errorMessage" class="notification is-danger">
            <button class="delete" @click="errorMessage = ''"></button>
            <span x-text="errorMessage"></span>
        </div>
        
        <!-- Upload Progress -->
        <div x-show="uploading" class="progress-container">
            <progress class="progress is-primary" 
                      :value="uploadProgress" 
                      max="100"></progress>
            <span x-text="`${uploadProgress}%`"></span>
        </div>
        
        <!-- Submit Button -->
        <button type="submit" 
                class="button is-primary" 
                :disabled="uploading || selectedFiles.length === 0">
            <span x-show="!uploading">Upload Files</span>
            <span x-show="uploading">Uploading...</span>
        </button>
    </form>
</div>
```

## Additional Widget Patterns

**Color Picker Widget:**
- HTMX endpoint for color palette
- Alpine.js state management
- Preview with CSS variables

**Icon Picker Widget:**
- Server-side icon search
- HTMX lazy loading
- FontAwesome integration

**Date Range Picker:**
- Alpine.js date state
- HTMX validation
- Server-side date formatting

---

**Integration Notes:**
- Widgets re-initialize after HTMX swaps using `htmx:afterSwap` event
- All validation happens server-side with client-side UX enhancements
- CSRF tokens included in all HTMX requests
- Error handling provides user feedback without breaking UX
