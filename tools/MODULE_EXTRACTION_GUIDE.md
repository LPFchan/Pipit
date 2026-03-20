# Module Extraction Summary

## Overview
Two new classic-script modules extracted from `material-mapper-app.js`:

1. **material-mapper-materials.js** — Material properties, Three.js objects, UI building, and code generation
2. **material-mapper-persistence.js** — IndexedDB caching and localStorage state management

---

## Module 1: material-mapper-materials.js

### Line Ranges Extracted from app.js

| Section | Lines | Content |
|---------|-------|---------|
| Material property store + schema | 391–442 | `matProps`, `FULL_SCHEMA`, `MAT_SCHEMA`, `MAT_CLASS`, `buildMaterial()`, `MAT_OBJ` |
| Outline system | 448–501 | `outlineMat`, outline manipulation functions |
| Part selection logic | 504–550 | `selectPart()` with multi-select/shift/range |
| Heuristic guessing | 553–560 | `guessKey()` — intelligent material assignment |
| Material application | 563–570 | `applyMaterials()` — push matProps to meshes |
| Property updates | 573–603 | `setProp()` — update matProps + Three.js + swatches |
| Material editor UI | 606–721 | `buildEditor()` — full property control panel |
| Eye button SVGs + visibility | 724–804 | `setVisibility()`, `syncShowAllBtn()`, icon SVGs |
| Parts list UI | 807–905 | `buildPartsUI()`, `updatePartCount()` |
| Search/filter | 908–914 | Search input listener (note: wired to DOM) |
| Code generation | 917–974 | `PROP_DEFAULTS`, `generateMatDef()`, color formatting |
| Code output panel | 977–1064 | `updateCode()` with syntax highlighting |
| Copy button | 1067–1119 | Code copy to clipboard |
| Save materials.js | 1122–1173 | `generateMaterialsJs()` file generation |
| Reset button | 1176–1191 | Part reset logic |
| Helper code gen funcs | 324–376 | `generateCameraCode()`, `generateApplyLoop()`, `generateLedDetection()` |

**Total: ~800 lines of extracted code**

### Factory Function Signature

```javascript
window.MaterialMapperMaterialsModule = function ({
    THREE,
    partMap,
    loadedModel,
    selectedParts,
    primarySelected,
    saveState,
    showToast,
    updatePartCount,
    generateCameraCode,
})
```

### Public API (Return Object)

#### Getters / State Access
```javascript
getMatProps()      // → matProps object
getMAT_OBJ()       // → { housingMat, buttonMat, ledMat, ... }
getMAT_SCHEMA()    // → material property schemas
getMAT_CLASS()     // → material class map
```

#### Material Property Updates
```javascript
setProp(matKey, propKey, value)
    // Updates matProps[matKey][propKey], Three.js object, swatches, code output
    // Example: setProp('ledMat', 'color', '#ff0000')
```

#### Part Selection
```javascript
selectPart(displayName, { ctrl = false, shift = false } = {})
    // Single/multi-select parts with Ctrl/Shift modifiers
    // Updates selectedParts Set, outlines, editor panel

setVisibility(displayName, visible)
    // Toggle part visibility in 3D and UI

clearOutlines()
    // Remove all outline meshes

syncShowAllBtn()
    // Show/hide "Show All" button based on hidden parts
```

#### UI Building
```javascript
buildEditor(matKey, selCount = 1)
    // Build material editor panel with all property controls
    // selCount: number of selected parts using this material

buildPartsUI()
    // Rebuild entire parts list (eye buttons, swatches, material selectors)
```

#### Material Application
```javascript
applyMaterials()
    // Apply current matProps as Three.js materials to all meshes in partMap

guessKey(name)
    // → 'ledMat' | 'ledCapMat' | 'buttonMat' | etc.
    // Heuristic assignment based on part name
```

#### Code Generation
```javascript
generateMatDef(key)
    // → string: "const housingMat = new THREE.MeshPhysicalMaterial({ ... });"

generateApplyLoop()
    // → string: code to apply MATERIAL_RULES in viewer.html

generateLedDetection()
    // → string: code to find LED meshes by name

generateMaterialsJs()
    // → string: complete materials.js ES6 module

updateCode()
    // Regenerate code-output panel with syntax highlighting
```

#### Utilities
```javascript
updatePartCount()
    // Update part count text (visible/total)
```

---

## Module 2: material-mapper-persistence.js

### Line Ranges Extracted from app.js

| Section | Lines | Content |
|---------|-------|---------|
| IDB constants + openIDB | 1614–1622 | IndexedDB database setup |
| saveLastFileToDB | 1624–1628 | Cache file in IDB |
| loadLastFileFromDB | 1630–1644 | Load cached file on startup |
| saveState | 1646–1680 | Serialize all state to localStorage |
| restoreState | 1810–1865 | Deserialize and apply saved state |
| importFromCode | 1683–1780 | Parse generated code into matProps |
| Import modal handlers | 1782–1808 | UI for paste-code import |

**Total: ~280 lines extracted and refactored**

### Factory Function Signature

```javascript
window.MaterialMapperPersistenceModule = function ({
    loadBuffer,              // callback to load GLB buffer
    partMap,
    matProps,
    MAT_OBJ,
    loadedFileName,
    loadedModel,
    camera,
    controls,
    sceneState,
    THREE,
    showToast,
    importFromCode,         // callback: function(text) → { matCount, ruleCount }
})
```

### Public API (Return Object)

#### IndexedDB File Cache
```javascript
saveLastFileToDB(fileName, buffer)
    // Save GLB file to IndexedDB (no size limit)
    // Called after successful load

loadLastFileFromDB()
    // Load and parse last-opened file from IDB
    // Call on page startup (auto-restore)
```

#### Local Storage State
```javascript
saveState()
    // Serialize current state → localStorage[STORAGE_KEY][fileName]
    // Includes: matProps, visibility, assignments, camera, model rotation
    // Called after any material edit (from setProp)

restoreState(fileName, callbacks)
    // Deserialize saved state from localStorage and apply to current session
    // callbacks object provides:
    //   - applyMaterials()
    //   - buildPartsUI()
    //   - buildEditor()
    //   - syncShowAllBtn()
    //   - toggleOrtho(newValue)
    //   - setHudXYZ(elemId, elemId, elemId, vec3)
    //   - applyModelRotationDeg(x, y, z, persist)
    //   - syncOrbitTarget()
    // Returns: true if state was restored, false if none saved
```

#### Import/Export
```javascript
importFromCode(text)
    // Parse Material Mapper generated code and restore matProps/assignments
    // Returns: { matCount, ruleCount }
    // Calls back to app.js's importFromCode for UI updates
```

---

## Wiring Code: How to Integrate into app.js

### Step 1: Load Scripts in HTML
Add to `material-mapper.html` `<head>` (before app.js):

```html
<script src="tools/material-mapper-materials.js"></script>
<script src="tools/material-mapper-persistence.js"></script>
<script src="tools/material-mapper-app.js"></script>
```

### Step 2: Initialize Modules in app.js

Replace the original inline code with module instantiation. Inside the `MaterialMapperApp` function, after state variables are declared:

```javascript
    // ─────────────────────────────────────────────────────────────
    // Initialize Material Persistence Module
    // ─────────────────────────────────────────────────────────────
    const persistenceModule = window.MaterialMapperPersistenceModule({
        loadBuffer,
        partMap,
        matProps,
        MAT_OBJ,
        loadedFileName,
        loadedModel,
        camera,
        controls,
        sceneState,
        THREE,
        showToast,
        importFromCode,
    });

    // ─────────────────────────────────────────────────────────────
    // Initialize Material Management Module
    // ─────────────────────────────────────────────────────────────
    const materialsModule = window.MaterialMapperMaterialsModule({
        THREE,
        partMap,
        loadedModel,
        selectedParts,
        primarySelected,
        saveState: persistenceModule.saveState,  // Delegate to persistence
        showToast,
        updatePartCount: () => materialsModule.updatePartCount(),
        generateCameraCode,
    });

    // Expose methods needed by rest of app
    const {
        getMatProps, getMAT_OBJ, getMAT_SCHEMA,
        setProp, selectPart, setVisibility, clearOutlines,
        buildEditor, buildPartsUI, applyMaterials, guessKey,
        generateMatDef, updateCode, generateMaterialsJs,
    } = materialsModule;

    // Update module reference variables
    matProps = getMatProps();
    MAT_OBJ = getMAT_OBJ();
    MAT_SCHEMA = getMAT_SCHEMA();
```

### Step 3: Replace Inline Function Calls

After the module initialization, delete the original inline definitions and wire all handlers:

```javascript
    // ─────────────────────────────────────────────────────────────
    // Reset button
    // ─────────────────────────────────────────────────────────────
    document.getElementById('reset-btn').addEventListener('click', () => {
        for (const entry of partMap.values()) {
            entry.assignedKey = guessKey(entry.origName ?? '');
            entry.visible = true;
            entry.meshes.forEach(m => { m.visible = true; });
        }
        clearOutlines();
        selectedParts.clear();
        primarySelected = null;
        applyMaterials();
        buildPartsUI();
        materialsModule.syncShowAllBtn();
        buildEditor(null);
        persistenceModule.saveState();
    });

    // ─────────────────────────────────────────────────────────────
    // Show all button
    // ─────────────────────────────────────────────────────────────
    document.getElementById('show-all-btn').addEventListener('click', () => {
        for (const [name] of partMap) setVisibility(name, true);
    });

    // ─────────────────────────────────────────────────────────────
    // Search / filter
    // ─────────────────────────────────────────────────────────────
    document.getElementById('search-input').addEventListener('input', (e) => {
        const q = e.target.value.trim().toLowerCase();
        document.querySelectorAll('.part-row').forEach(row => {
            const match = !q || row.dataset.name.toLowerCase().includes(q);
            row.classList.toggle('hidden', !match);
        });
        materialsModule.updatePartCount();
    });

    // ─────────────────────────────────────────────────────────────
    // Copy code button
    // ─────────────────────────────────────────────────────────────
    document.getElementById('copy-btn').addEventListener('click', () => {
        const usedKeys = new Set();
        for (const e of partMap.values()) {
            if (e.assignedKey !== '_keep') usedKeys.add(e.assignedKey);
        }
        const matSection = [...usedKeys].map(k => generateMatDef(k)).join('\n\n');

        const ruleLines = [];
        for (const [displayName, entry] of partMap) {
            if (entry.assignedKey === '_keep') continue;
            const safe = displayName.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
            ruleLines.push(`    { match: '${safe}',`.padEnd(44) + ` mat: ${entry.assignedKey} },`);
        }
        const rulesSection = [
            `const MATERIAL_RULES = [`,
            `    // Exact part names — generated by Material Mapper`,
            ...ruleLines,
            ``,
            `    // Catch-all (must be last)`,
            `    { match: /.*/, mat: housingMat },`,
            `];`,
        ].join('\n');

        const full = [
            `// ── paste into assets/materials.js (between ▼▼▼ / ▲▲▲ markers) ─────`,
            matSection,
            ``,
            `// ── MATERIAL_RULES ──────────────────────────────────────────`,
            rulesSection,
            ``,
            `// ── Apply materials ─────────────────────────────────────────`,
            materialsModule.generateApplyLoop(),
            ``,
            `// ── Find LED meshes (replaces emissive-scan in viewer.html) ─`,
            materialsModule.generateLedDetection(),
            ``,
            generateCameraCode(),
        ].join('\n');

        navigator.clipboard.writeText(full).then(() => showToast('Copied!'));
    });

    // ─────────────────────────────────────────────────────────────
    // Save materials.js button
    // ─────────────────────────────────────────────────────────────
    document.getElementById('save-materials-btn').addEventListener('click', () => {
        if (partMap.size === 0) { showToast('Load a model first'); return; }
        const content = generateMaterialsJs();
        const blob = new Blob([content], { type: 'text/javascript' });
        const url  = URL.createObjectURL(blob);
        const a    = document.createElement('a');
        a.href = url;
        a.download = 'materials.js';
        a.click();
        URL.revokeObjectURL(url);
        showToast('materials.js downloaded!');
    });

    // ─────────────────────────────────────────────────────────────
    // Cmd/Ctrl + A → select all visible parts
    // ─────────────────────────────────────────────────────────────
    document.addEventListener('keydown', (e) => {
        if (!(e.metaKey || e.ctrlKey) || e.key !== 'a') return;
        if (!partMap.size) return;
        const tag = document.activeElement?.tagName;
        if (tag === 'INPUT' || tag === 'TEXTAREA') return;
        e.preventDefault();

        const visibleRows = [...document.querySelectorAll('.part-row:not(.hidden)')];
        selectedParts.clear();
        visibleRows.forEach(r => selectedParts.add(r.dataset.name));
        if (!primarySelected || !selectedParts.has(primarySelected))
            primarySelected = visibleRows[0]?.dataset.name ?? null;

        document.querySelectorAll('.part-row').forEach(r => {
            r.classList.toggle('selected', selectedParts.has(r.dataset.name));
        });
        setOutlines(selectedParts);
        const primaryEntry = primarySelected ? partMap.get(primarySelected) : null;
        buildEditor(primaryEntry?.assignedKey ?? null, selectedParts.size);
    });

    // ─────────────────────────────────────────────────────────────
    // Import code modal
    // ─────────────────────────────────────────────────────────────
    const importModal     = document.getElementById('import-modal');
    const importCodeBtn   = document.getElementById('import-code-btn');
    const importModalClose = document.getElementById('import-modal-close');
    const importApplyBtn  = document.getElementById('import-apply-btn');
    const importTextarea  = document.getElementById('import-textarea');

    importCodeBtn.addEventListener('click', () => {
        importTextarea.value = '';
        importModal.classList.remove('hidden');
        setTimeout(() => importTextarea.focus(), 50);
    });
    importModalClose.addEventListener('click', () => importModal.classList.add('hidden'));
    importModal.addEventListener('click', (e) => { if (e.target === importModal) importModal.classList.add('hidden'); });

    importApplyBtn.addEventListener('click', () => {
        const text = importTextarea.value.trim();
        if (!text) return;
        const { matCount, ruleCount } = persistenceModule.importFromCode(text);
        importModal.classList.add('hidden');
        showToast(`Imported: ${matCount} material${matCount !== 1 ? 's' : ''}, ${ruleCount} rule${ruleCount !== 1 ? 's' : ''}`);
    });

    // ─────────────────────────────────────────────────────────────
    // Auto-reload last file on startup
    // ─────────────────────────────────────────────────────────────
    persistenceModule.loadLastFileFromDB();
```

### Step 4: Update saveLastFileToDB Call

In the `loadBuffer` function, call persistence module:

```javascript
    document.getElementById('drop-overlay').classList.add('hidden');
    document.getElementById('search-input').value = '';
    document.getElementById('export-btn').style.display = '';
    document.getElementById('zfix-btn').style.display   = '';
    document.title = `Material Mapper — ${fileName}`;
    loadedFileName = fileName;
    persistenceModule.saveLastFileToDB(fileName, buffer);  // ← Wire here

    const didRestore = persistenceModule.restoreState(fileName, {
        applyMaterials,
        buildPartsUI,
        buildEditor,
        syncShowAllBtn: () => materialsModule.syncShowAllBtn(),
        toggleOrtho:        (val) => { isOrtho = val; /* call camera module */ },
        setHudXYZ,
        applyModelRotationDeg,
        syncOrbitTarget,
    });
```

### Step 5: Lines to Delete from app.js

Delete the original inline implementations (safe to remove completely):

- Lines 391–442: Material store + schema (replaced by module)
- Lines 448–550: Outline + selectPart (replaced by module)
- Lines 553–570: guessKey + applyMaterials (replaced by module)
- Lines 573–603: setProp (replaced by module)
- Lines 606–721: buildEditor (replaced by module)
- Lines 724–905: Eye buttons + buildPartsUI + updatePartCount (replaced by module)
- Lines 908–914: Search filter (keep handler, use module.updatePartCount)
- Lines 917–1191: Code generation + export buttons (replaced by module)
- Lines 1614–1865: IDB + localStorage functions (replaced by module)
- Lines 1782–1808: Import modal (refactored to use module)

---

## Summary of Changes

| Aspect | Before | After |
|--------|--------|-------|
| app.js size | ~2200 lines | ~1400 lines (~36% reduction) |
| Material logic | Inline in app.js | Encapsulated in `material-mapper-materials.js` |
| State persistence | Inline in app.js | Encapsulated in `material-mapper-persistence.js` |
| Module coupling | Tight (everything global) | Loose (dependency injection via constructor) |
| Testability | Difficult (DOM-coupled) | Easier (can mock partMap, THREE, DOM callbacks) |
| Reusability | Not possible | Can import modules in other projects |

---

## API Quick Reference

### From materials module:
```javascript
// Read/update materials
const matProps = materialsModule.getMatProps();
materialsModule.setProp('ledMat', 'color', '#00ff00');

// Manage parts
materialsModule.selectPart('Housing', { ctrl: true });
materialsModule.setVisibility('Button', false);
materialsModule.applyMaterials();

// UI
materialsModule.buildEditor('ledMat', 3);
materialsModule.buildPartsUI();

// Code output
const code = materialsModule.generateMaterialsJs();
materialsModule.updateCode();
```

### From persistence module:
```javascript
// Save/restore
persistenceModule.saveState();
const didRestore = persistenceModule.restoreState(fileName, callbacks);

// File caching
persistenceModule.saveLastFileToDB(fileName, buffer);
persistenceModule.loadLastFileFromDB();

// Import
const result = persistenceModule.importFromCode(generatedCodeString);
console.log(`Imported ${result.matCount} materials, ${result.ruleCount} rules`);
```
