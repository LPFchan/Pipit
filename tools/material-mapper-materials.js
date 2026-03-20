'use strict';

/**
 * Material Mapper Materials Module
 * 
 * Encapsulates material property management, Three.js material objects,
 * UI building (parts list + editor), and code generation.
 * 
 * Module Factory: window.MaterialMapperMaterialsModule
 * Dependencies passed via constructor:
 *   - THREE: Three.js library
 *   - partMap: Map of displayName → { meshes, origMats, origName, assignedKey, visible }
 *   - loadedModel: current Three.js model or null
 *   - saveState: callback function
 *   - showToast: callback function
 *   - updatePartCount: callback function (or handled internally)
 *   - generateCameraCode: function that returns camera setup code
 */
window.MaterialMapperMaterialsModule = function ({
    THREE,
    partMap,
    loadedModel,
    saveState,
    showToast,
    updatePartCount,
    generateCameraCode,
}) {
    const selectedParts = new Set();
    let primarySelected = null;

    function getPrimarySelected() {
        return primarySelected;
    }

    function assignPrimarySelected(value) {
        primarySelected = value;
    }

    // ─────────────────────────────────────────────────────────────
    // Material property store + schema
    //
    // matProps holds the current values for each material.
    // These drive both the live Three.js objects and the code output.
    // Editing in the UI calls setProp() which updates both.
    // ─────────────────────────────────────────────────────────────
    // All 7 materials share the same full property set.
    // Every property is editable; code gen skips Three.js defaults.
    const matProps = {
        housingMat: { color: '#181b2a', roughness: 0.50, metalness: 0.00, emissive: '#000000', emissiveIntensity: 0.0, transmission: 0.22, thickness: 0.009, ior: 1.49, opacity: 1.0, transparent: true,  toneMapped: true,  side: 'Double', polygonOffset: false, polygonOffsetFactor: 0, polygonOffsetUnits: 0 },
        buttonMat:  { color: '#23263a', roughness: 0.18, metalness: 0.04, emissive: '#000000', emissiveIntensity: 0.0, transmission: 0.00, thickness: 0.0,   ior: 1.50, opacity: 1.0, transparent: false, toneMapped: true,  side: 'Front',  polygonOffset: false, polygonOffsetFactor: 0, polygonOffsetUnits: 0 },
        ledMat:     { color: '#00ff45', roughness: 0.10, metalness: 0.00, emissive: '#00ff45', emissiveIntensity: 4.0, transmission: 0.00, thickness: 0.0,   ior: 1.50, opacity: 1.0, transparent: false, toneMapped: false, side: 'Front',  polygonOffset: false, polygonOffsetFactor: 0, polygonOffsetUnits: 0 },
        ledCapMat:  { color: '#ffffff', roughness: 0.60, metalness: 0.00, emissive: '#000000', emissiveIntensity: 0.0, transmission: 0.80, thickness: 0.001, ior: 1.50, opacity: 0.88, transparent: true,  toneMapped: false, side: 'Front',  polygonOffset: false, polygonOffsetFactor: 0, polygonOffsetUnits: 0 },
        pcbMat:     { color: '#1b3a1e', roughness: 0.88, metalness: 0.08, emissive: '#000000', emissiveIntensity: 0.0, transmission: 0.00, thickness: 0.0,   ior: 1.50, opacity: 1.0, transparent: false, toneMapped: true,  side: 'Front',  polygonOffset: true,  polygonOffsetFactor: -2, polygonOffsetUnits: -2 },
        metalMat:   { color: '#b8a870', roughness: 0.22, metalness: 0.92, emissive: '#000000', emissiveIntensity: 0.0, transmission: 0.00, thickness: 0.0,   ior: 1.50, opacity: 1.0, transparent: false, toneMapped: true,  side: 'Front',  polygonOffset: true,  polygonOffsetFactor: -1, polygonOffsetUnits: -1 },
        rubberMat:  { color: '#101010', roughness: 0.96, metalness: 0.00, emissive: '#000000', emissiveIntensity: 0.0, transmission: 0.00, thickness: 0.0,   ior: 1.50, opacity: 1.0, transparent: false, toneMapped: true,  side: 'Front',  polygonOffset: false, polygonOffsetFactor: 0, polygonOffsetUnits: 0 },
    };

    // Shared full schema — same for all materials
    const FULL_SCHEMA = [
        { key: 'color',             type: 'color',                                    label: 'Color'        },
        { key: 'emissive',          type: 'color',                                    label: 'Emissive'     },
        { key: 'emissiveIntensity', type: 'range', min: 0,   max: 10,  step: 0.1,    label: 'Emissive ×'   },
        { key: 'roughness',         type: 'range', min: 0,   max: 1,   step: 0.01,   label: 'Roughness'    },
        { key: 'metalness',         type: 'range', min: 0,   max: 1,   step: 0.01,   label: 'Metalness'    },
        { key: 'transmission',      type: 'range', min: 0,   max: 1,   step: 0.01,   label: 'Transmission' },
        { key: 'thickness',         type: 'range', min: 0,   max: 0.1, step: 0.001,  label: 'Thickness'    },
        { key: 'ior',               type: 'range', min: 1.0, max: 2.5, step: 0.01,   label: 'IOR'          },
        { key: 'opacity',           type: 'range', min: 0,   max: 1,   step: 0.01,   label: 'Opacity'      },
        { key: 'transparent',          type: 'toggle',                                    label: 'Transparent'     },
        { key: 'toneMapped',           type: 'toggle',                                    label: 'Tone Mapped'     },
        { key: 'side',                 type: 'select', options: ['Front', 'Double'],      label: 'Side'            },
        { key: 'polygonOffset',        type: 'toggle',                                    label: 'Poly Offset'     },
        { key: 'polygonOffsetFactor',  type: 'range',  min: -10, max: 10, step: 1,       label: 'Offset Factor'   },
        { key: 'polygonOffsetUnits',   type: 'range',  min: -10, max: 10, step: 1,       label: 'Offset Units'    },
    ];
    const MAT_SCHEMA = {};
    for (const key of Object.keys(matProps)) MAT_SCHEMA[key] = FULL_SCHEMA;

    // All materials are MeshPhysicalMaterial (Physical is a superset of Standard)
    const MAT_CLASS = {};
    for (const key of Object.keys(matProps)) MAT_CLASS[key] = 'MeshPhysicalMaterial';

    // ─────────────────────────────────────────────────────────────
    // Live Three.js material objects — built from matProps
    // ─────────────────────────────────────────────────────────────
    function buildMaterial(key) {
        const p = matProps[key];
        return new THREE.MeshPhysicalMaterial({
            color:             new THREE.Color(p.color),
            roughness:         p.roughness,
            metalness:         p.metalness,
            emissive:          new THREE.Color(p.emissive),
            emissiveIntensity: p.emissiveIntensity,
            transmission:      p.transmission,
            thickness:         p.thickness,
            ior:               p.ior,
            opacity:           p.opacity,
            transparent:          p.transparent,
            toneMapped:           p.toneMapped,
            side:                 p.side === 'Double' ? THREE.DoubleSide : THREE.FrontSide,
            polygonOffset:        p.polygonOffset        ?? false,
            polygonOffsetFactor:  p.polygonOffsetFactor  ?? 0,
            polygonOffsetUnits:   p.polygonOffsetUnits   ?? 0,
        });
    }

    const MAT_OBJ = {};
    for (const key of Object.keys(matProps)) {
        MAT_OBJ[key] = buildMaterial(key);
    }

    // ─────────────────────────────────────────────────────────────
    // Outline highlight
    // Technique: invisible back-face mesh parented to the selected
    // mesh, scaled slightly larger.  Works with WebGPU renderer
    // without any post-processing pass.
    // ─────────────────────────────────────────────────────────────
    const outlineMat = new THREE.MeshBasicMaterial({
        color:     0x4d7aff,
        side:      THREE.BackSide,
        depthTest: true,
        toneMapped: false,
    });

    const _outlineHosts = new Set();   // meshes currently hosting outline children

    function clearOutlines() {
        for (const mesh of _outlineHosts) {
            mesh.children
                .filter(c => c.userData.isOutline)
                .forEach(c => mesh.remove(c));
        }
        _outlineHosts.clear();
    }

    function addOutline(mesh) {
        if (!mesh || _outlineHosts.has(mesh)) return;
        const ol = new THREE.Mesh(mesh.geometry, outlineMat);
        ol.scale.setScalar(1.035);
        ol.userData.isOutline = true;
        mesh.add(ol);
        _outlineHosts.add(mesh);
    }

    function setOutlines(names) {
        clearOutlines();
        for (const name of names) {
            const entry = partMap.get(name);
            if (entry) entry.meshes.forEach(addOutline);
        }
    }

    function syncSelectionUI({ scroll = true } = {}) {
        const currentPrimarySelected = getPrimarySelected();

        document.querySelectorAll('.part-row').forEach((row) => {
            row.classList.toggle('selected', selectedParts.has(row.dataset.name));
        });

        if (scroll && currentPrimarySelected) {
            const row = document.querySelector(`.part-row[data-name="${CSS.escape(currentPrimarySelected)}"]`);
            if (row) row.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
        }

        setOutlines(selectedParts);
        const primaryEntry = currentPrimarySelected ? partMap.get(currentPrimarySelected) : null;
        buildEditor(primaryEntry?.assignedKey ?? null, selectedParts.size);
    }

    function clearSelection() {
        selectedParts.clear();
        assignPrimarySelected(null);
        document.querySelectorAll('.part-row').forEach((row) => row.classList.remove('selected'));
        clearOutlines();
        buildEditor(null);
    }

    function selectAllVisible() {
        const visibleRows = [...document.querySelectorAll('.part-row:not(.hidden)')];
        if (!visibleRows.length) {
            clearSelection();
            return;
        }

        selectedParts.clear();
        visibleRows.forEach((row) => selectedParts.add(row.dataset.name));
        if (!getPrimarySelected() || !selectedParts.has(getPrimarySelected())) {
            assignPrimarySelected(visibleRows[0]?.dataset.name ?? null);
        }
        syncSelectionUI();
    }

    function selectMesh(mesh, modifiers = {}) {
        if (!mesh) return false;
        for (const [displayName, entry] of partMap) {
            if (entry.meshes.includes(mesh)) {
                selectPart(displayName, modifiers);
                return true;
            }
        }
        return false;
    }

    function syncSelectionEditor() {
        const currentPrimarySelected = getPrimarySelected();
        const primaryEntry = currentPrimarySelected ? partMap.get(currentPrimarySelected) : null;
        buildEditor(primaryEntry?.assignedKey ?? null, selectedParts.size);
    }

    // ─────────────────────────────────────────────────────────────
    // Heuristic initial guess (mirrors viewer.html patterns)
    // ─────────────────────────────────────────────────────────────
    function guessKey(name) {
        const n = name.toLowerCase();
        if (/led|rgb|emitter|die/.test(n))                              return 'ledMat';
        if (/diffuser|lens|cap|dome/.test(n))                           return 'ledCapMat';
        if (/button|btn|trigger/.test(n))                               return 'buttonMat';
        if (/pcb|board|substrate|fr4/.test(n))                          return 'pcbMat';
        if (/clip|spring|pin|contact|metal|brass|steel|screw|nut/.test(n)) return 'metalMat';
        if (/rubber|gasket|seal|grip/.test(n))                          return 'rubberMat';
        return 'housingMat';
    }

    // ─────────────────────────────────────────────────────────────
    // Apply materials to all meshes
    // ─────────────────────────────────────────────────────────────
    function applyMaterials() {
        for (const entry of partMap.values()) {
            const mat = entry.assignedKey === '_keep' ? null : (MAT_OBJ[entry.assignedKey] ?? null);
            entry.meshes.forEach((m, i) => {
                if (m.userData.isOutline) return;
                m.material = mat ?? entry.origMats[i];
            });
        }
    }

    // ─────────────────────────────────────────────────────────────
    // setProp — central material property update
    // Updates matProps, the Three.js object, swatch, and code
    // ─────────────────────────────────────────────────────────────
    function setProp(matKey, propKey, value) {
        matProps[matKey][propKey] = value;
        const mat = MAT_OBJ[matKey];
        if (!mat) return;

        if (propKey === 'color') {
            mat.color.set(value);
        } else if (propKey === 'emissive') {
            mat.emissive.set(value);
        } else if (propKey === 'side') {
            mat.side = value === 'Double' ? THREE.DoubleSide : THREE.FrontSide;
        } else if (typeof value === 'boolean') {
            mat[propKey] = value;
        } else {
            mat[propKey] = parseFloat(value);
        }
        mat.needsUpdate = true;

        // Refresh swatches for all rows using this material
        document.querySelectorAll(`.swatch[data-mat="${matKey}"]`).forEach(el => {
            el.style.background = matProps[matKey].color;
        });

        updateCode();
        saveState();
    }

    // ─────────────────────────────────────────────────────────────
    // Build material editor for the given matKey
    // ─────────────────────────────────────────────────────────────
    function buildEditor(matKey, selCount = 1) {
        const body    = document.getElementById('editor-body');
        const tag     = document.getElementById('editor-mat-tag');
        const affects = document.getElementById('editor-affects');

        body.innerHTML = '';

        if (!matKey || matKey === '_keep') {
            tag.textContent     = matKey === '_keep' ? '_keep' : '—';
            affects.textContent = matKey === '_keep' ? 'keeping Onshape material' : '';
            body.innerHTML = `<div class="editor-placeholder">
                ${matKey === '_keep' ? 'Original Onshape material is preserved' : 'Click a part to edit its material'}
            </div>`;
            return;
        }

        tag.textContent = matKey;

        if (selCount > 1) {
            affects.textContent = `${selCount} selected`;
        } else {
            // Count how many parts use this material
            let usageCount = 0;
            for (const e of partMap.values()) {
                if (e.assignedKey === matKey) usageCount++;
            }
            affects.textContent = `affects ${usageCount} part${usageCount !== 1 ? 's' : ''}`;
        }

        const schema = MAT_SCHEMA[matKey] ?? [];
        for (const propDef of schema) {
            const row = document.createElement('div');
            row.className = 'prop-row';

            const lbl = document.createElement('label');
            lbl.className   = 'prop-label';
            lbl.textContent = propDef.label;
            row.appendChild(lbl);

            if (propDef.type === 'color') {
                const wrap   = document.createElement('div');
                wrap.className = 'prop-color-wrap';

                const picker = document.createElement('input');
                picker.type  = 'color';
                picker.className = 'prop-color';
                picker.value = matProps[matKey][propDef.key] ?? '#ffffff';

                const hexSpan = document.createElement('span');
                hexSpan.className   = 'prop-hex';
                hexSpan.textContent = picker.value;

                picker.addEventListener('input', () => {
                    hexSpan.textContent = picker.value;
                    setProp(matKey, propDef.key, picker.value);
                });

                wrap.appendChild(picker);
                wrap.appendChild(hexSpan);
                row.appendChild(wrap);

            } else if (propDef.type === 'toggle') {
                const cb = document.createElement('input');
                cb.type      = 'checkbox';
                cb.className = 'prop-toggle';
                cb.checked   = !!matProps[matKey][propDef.key];
                cb.addEventListener('change', () => setProp(matKey, propDef.key, cb.checked));
                row.appendChild(cb);

            } else if (propDef.type === 'select') {
                const sel = document.createElement('select');
                sel.className = 'prop-select';
                for (const opt of propDef.options) {
                    const o = document.createElement('option');
                    o.value = opt; o.textContent = opt;
                    sel.appendChild(o);
                }
                sel.value = matProps[matKey][propDef.key] ?? propDef.options[0];
                sel.addEventListener('change', () => setProp(matKey, propDef.key, sel.value));
                row.appendChild(sel);

            } else { // 'range'
                const slider = document.createElement('input');
                slider.type      = 'range';
                slider.className = 'prop-slider';
                slider.min   = propDef.min;
                slider.max   = propDef.max;
                slider.step  = propDef.step;
                slider.value = matProps[matKey][propDef.key] ?? 0;

                const num = document.createElement('input');
                num.type      = 'number';
                num.className = 'prop-num';
                num.min   = propDef.min;
                num.max   = propDef.max;
                num.step  = propDef.step;
                num.value = matProps[matKey][propDef.key] ?? 0;

                slider.addEventListener('input', () => {
                    const v = parseFloat(slider.value);
                    num.value = v;
                    setProp(matKey, propDef.key, v);
                });
                num.addEventListener('change', () => {
                    const v = Math.max(propDef.min, Math.min(propDef.max, parseFloat(num.value) || 0));
                    num.value    = v;
                    slider.value = v;
                    setProp(matKey, propDef.key, v);
                });

                row.appendChild(slider);
                row.appendChild(num);
            }

            body.appendChild(row);
        }
    }

    // ─────────────────────────────────────────────────────────────
    // selectPart — shared by row click AND canvas raycaster click
    // ─────────────────────────────────────────────────────────────
    function selectPart(displayName, { ctrl = false, shift = false } = {}) {
        if (!partMap.has(displayName)) return;

        let currentPrimarySelected = getPrimarySelected();

        if (shift && currentPrimarySelected) {
            // Range select: include all visible rows between anchor and target
            const rows  = [...document.querySelectorAll('.part-row:not(.hidden)')];
            const names = rows.map(r => r.dataset.name);
            const a = names.indexOf(currentPrimarySelected);
            const b = names.indexOf(displayName);
            if (a !== -1 && b !== -1) {
                const [lo, hi] = a < b ? [a, b] : [b, a];
                for (let i = lo; i <= hi; i++) selectedParts.add(names[i]);
            }
            // anchor stays for further shift-clicks
        } else if (ctrl) {
            // Toggle individual item
            if (selectedParts.has(displayName)) {
                selectedParts.delete(displayName);
                if (currentPrimarySelected === displayName) {
                    currentPrimarySelected = selectedParts.size > 0 ? [...selectedParts].at(-1) : null;
                    assignPrimarySelected(currentPrimarySelected);
                }
            } else {
                selectedParts.add(displayName);
                currentPrimarySelected = displayName;
                assignPrimarySelected(currentPrimarySelected);
            }
        } else {
            // Plain click → single select
            selectedParts.clear();
            selectedParts.add(displayName);
            currentPrimarySelected = displayName;
            assignPrimarySelected(currentPrimarySelected);
        }

        syncSelectionUI();
    }

    // ─────────────────────────────────────────────────────────────
    // Visibility toggle
    // ─────────────────────────────────────────────────────────────
    const EYE_OPEN_SVG = `<svg width="14" height="10" viewBox="0 0 14 10" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M1 5C2.6 2 4.6 1 7 1C9.4 1 11.4 2 13 5C11.4 8 9.4 9 7 9C4.6 9 2.6 8 1 5Z" stroke="currentColor" stroke-width="1.3"/><circle cx="7" cy="5" r="1.8" fill="currentColor"/></svg>`;
    const EYE_SHUT_SVG = `<svg width="14" height="10" viewBox="0 0 14 10" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M1 5C2.6 2 4.6 1 7 1C9.4 1 11.4 2 13 5" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/><line x1="2" y1="9" x2="12" y2="1" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/></svg>`;

    function syncShowAllBtn() {
        const anyHidden = [...partMap.values()].some(e => !e.visible);
        document.getElementById('show-all-btn').style.display = anyHidden ? '' : 'none';
    }

    function setVisibility(displayName, visible) {
        const entry = partMap.get(displayName);
        if (!entry) return;
        entry.visible = visible;
        entry.meshes.forEach(m => { m.visible = visible; });

        const row = document.querySelector(`.part-row[data-name="${CSS.escape(displayName)}"]`);
        if (row) {
            row.classList.toggle('invisible', !visible);
            const btn = row.querySelector('.eye-btn');
            if (btn) btn.innerHTML = visible ? EYE_OPEN_SVG : EYE_SHUT_SVG;
        }
        syncShowAllBtn();
        saveState();
    }

    // ─────────────────────────────────────────────────────────────
    // Build parts list
    // ─────────────────────────────────────────────────────────────
    function buildPartsUI() {
        const list  = document.getElementById('parts-list');
        const empty = document.getElementById('empty-state');
        empty.style.display = 'none';
        [...list.querySelectorAll('.part-row')].forEach(el => el.remove());
        document.getElementById('reset-btn').style.display = '';

        for (const [displayName, entry] of partMap) {
            const row = document.createElement('div');
            row.className = 'part-row';
            row.dataset.name = displayName;
            if (!entry.visible) row.classList.add('invisible');
            if (selectedParts.has(displayName)) row.classList.add('selected');

            // Eye (visibility) button
            const eyeBtn = document.createElement('button');
            eyeBtn.className = 'eye-btn';
            eyeBtn.title     = 'Toggle visibility';
            eyeBtn.innerHTML = entry.visible ? EYE_OPEN_SVG : EYE_SHUT_SVG;
            eyeBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                const newVis = !entry.visible;
                if (selectedParts.has(displayName) && selectedParts.size > 1) {
                    for (const name of selectedParts) setVisibility(name, newVis);
                } else {
                    setVisibility(displayName, newVis);
                }
            });

            // Swatch
            const swatch = document.createElement('div');
            swatch.className    = 'swatch';
            swatch.dataset.mat  = entry.assignedKey;
            swatch.style.background = entry.assignedKey === '_keep'
                ? 'transparent'
                : matProps[entry.assignedKey]?.color ?? '#444';
            if (entry.assignedKey === '_keep') swatch.style.border = '1px dashed #404060';

            // Name
            const nameEl = document.createElement('div');
            nameEl.className   = 'part-name' + (displayName.startsWith('(') ? ' unnamed' : '');
            nameEl.textContent = displayName;
            nameEl.title       = displayName;

            // Material selector
            const sel = document.createElement('select');
            sel.className = 'mat-select';
            const options = [
                ['housingMat', 'Housing — plastic'],
                ['buttonMat',  'Button — glossy'],
                ['ledMat',     'LED die — emissive'],
                ['ledCapMat',  'LED cap — diffuser'],
                ['pcbMat',     'PCB — FR4'],
                ['metalMat',   'Metal — contacts'],
                ['rubberMat',  'Rubber — gasket'],
                ['_keep',      '— keep original —'],
            ];
            for (const [val, label] of options) {
                const opt = document.createElement('option');
                opt.value       = val;
                opt.textContent = label;
                if (val === entry.assignedKey) opt.selected = true;
                sel.appendChild(opt);
            }

            sel.addEventListener('change', (e) => {
                e.stopPropagation();    // don't trigger row click
                const key = sel.value;

                // Apply to all selected parts if this part is among them
                const targets = (selectedParts.has(displayName) && selectedParts.size > 1)
                    ? [...selectedParts]
                    : [displayName];

                for (const name of targets) {
                    const tEntry = partMap.get(name);
                    if (!tEntry) continue;
                    tEntry.assignedKey = key;

                    // Sync swatch + dropdown for each affected row
                    const tRow = document.querySelector(`.part-row[data-name="${CSS.escape(name)}"]`);
                    if (tRow) {
                        const tSwatch = tRow.querySelector('.swatch');
                        if (tSwatch) {
                            tSwatch.dataset.mat      = key;
                            tSwatch.style.background = key === '_keep' ? 'transparent' : (matProps[key]?.color ?? '#444');
                            tSwatch.style.border     = key === '_keep' ? '1px dashed #404060' : '1px solid rgba(255,255,255,.12)';
                        }
                        const tSel = tRow.querySelector('.mat-select');
                        if (tSel && name !== displayName) tSel.value = key;
                    }
                }

                applyMaterials();

                // Refresh editor
                const currentPrimarySelected = getPrimarySelected();
                if (selectedParts.has(displayName) || currentPrimarySelected === displayName) {
                    const pEntry = currentPrimarySelected ? partMap.get(currentPrimarySelected) : null;
                    buildEditor(pEntry?.assignedKey ?? key, selectedParts.size);
                }

                updateCode();
                saveState();
            });

            // Row click → select (pass keyboard modifiers)
            row.addEventListener('click', (e) => selectPart(displayName, { ctrl: e.ctrlKey || e.metaKey, shift: e.shiftKey }));

            row.appendChild(eyeBtn);
            row.appendChild(swatch);
            row.appendChild(nameEl);
            row.appendChild(sel);
            list.appendChild(row);
        }

        updatePartCount();
        updateCode();
    }

    function _updatePartCount() {
        const total   = partMap.size;
        const visible = [...document.querySelectorAll('.part-row:not(.hidden)')].length;
        document.getElementById('part-count').textContent =
            visible < total ? `${visible} / ${total}` : `${total} part${total !== 1 ? 's' : ''}`;
    }

    // ─────────────────────────────────────────────────────────────
    // Generate code output
    // ─────────────────────────────────────────────────────────────
    function colorToHex(cssHex) {
        // '#181b2a' → '0x181b2a'
        return '0x' + cssHex.replace('#', '');
    }

    function fmtVal(v) {
        if (typeof v === 'number') {
            // show enough precision without trailing zeros
            return Number.isInteger(v) ? v.toFixed(1) : parseFloat(v.toPrecision(4)).toString();
        }
        return String(v);
    }

    // Three.js MeshPhysicalMaterial defaults — skip these in generated code
    const PROP_DEFAULTS = {
        emissive: '#000000', emissiveIntensity: 0, transmission: 0,
        thickness: 0, ior: 1.5, opacity: 1, transparent: false,
        toneMapped: true, side: 'Front', metalness: 0,
        polygonOffset: false, polygonOffsetFactor: 0, polygonOffsetUnits: 0,
    };

    function generateMatDef(key) {
        const p      = matProps[key];
        const schema = MAT_SCHEMA[key] ?? [];
        const lines  = [];

        for (const propDef of schema) {
            const propKey = propDef.key;
            const raw     = p[propKey];
            if (raw === undefined) continue;

            // Skip values that match Three.js defaults (keeps output tidy)
            if (propKey in PROP_DEFAULTS) {
                const def = PROP_DEFAULTS[propKey];
                if (typeof def === 'number'  && Math.abs(raw - def) < 1e-9) continue;
                if (typeof def === 'boolean' && raw === def) continue;
                if (typeof def === 'string'  && raw === def) continue;
            }

            let valueStr;
            if (propDef.type === 'color') {
                valueStr = colorToHex(raw);
            } else if (propDef.type === 'select' && propKey === 'side') {
                valueStr = raw === 'Double' ? 'THREE.DoubleSide' : 'THREE.FrontSide';
            } else if (propDef.type === 'toggle') {
                valueStr = raw ? 'true' : 'false';
            } else {
                valueStr = fmtVal(raw);
            }

            lines.push(`    ${(propKey + ':').padEnd(22)} ${valueStr},`);
        }

        return `const ${key} = new THREE.MeshPhysicalMaterial({\n${lines.join('\n')}\n});`;
    }

    function generateApplyLoop() {
        return [
            `rootModel.traverse((obj) => {`,
            `    if (!obj.isMesh) return;`,
            `    // Layout A (named parent group) or Layout B (flat mesh) — mirror mapper's name selection.`,
            `    const isParentRoot = !obj.parent || obj.parent === rootModel;`,
            `    const nameToMatch  = (!isParentRoot && obj.parent.name) ? obj.parent.name : obj.name;`,
            `    const rule = MATERIAL_RULES.find(r =>`,
            `        typeof r.match === 'string' ? nameToMatch === r.match : r.match.test(nameToMatch));`,
            `    if (rule) { obj.material = rule.mat; obj.material.needsUpdate = true; }`,
            `});`,
        ].join('\n');
    }

    function generateLedDetection() {
        const ledNames = [];
        for (const [displayName, entry] of partMap) {
            if (entry.assignedKey === 'ledMat') ledNames.push(entry.origName ?? displayName);
        }
        const setLiteral = ledNames.map(n => `'${n.replace(/\\/g, '\\\\').replace(/'/g, "\\'")}'`).join(', ');
        return [
            `const LED_NAMES = new Set([${setLiteral}]);`,
            `rootModel.traverse((obj) => {`,
            `    if (!obj.isMesh) return;`,
            `    const isParentRoot = !obj.parent || obj.parent === rootModel;`,
            `    const nameToMatch  = (!isParentRoot && obj.parent.name) ? obj.parent.name : obj.name;`,
            `    if (LED_NAMES.has(nameToMatch)) ledMeshes.push(obj);`,
            `});`,
        ].join('\n');
    }

    function updateCode() {
        const pre = document.getElementById('code-output');
        if (partMap.size === 0) {
            pre.innerHTML = `<span class="cmt">// Load a model first</span>`;
            return;
        }

        // Which material keys are actually used?
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

        // Syntax-highlight for display
        function hlLine(line) {
            return line
                .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
                .replace(/\b(const|new)\b/g, '<span class="kw">$1</span>')
                .replace(/(THREE\.\w+)/g, '<span class="key">$1</span>')
                .replace(/(0x[0-9a-fA-F]+)/g, '<span class="val">$1</span>')
                .replace(/('(?:[^'\\]|\\.)*')/g, '<span class="str">$1</span>')
                .replace(/(\/\/.*)/g, '<span class="cmt">$1</span>');
        }

        const allLines = [
            `// ── paste into assets/materials.js (between ▼▼▼ / ▲▲▲ markers) ─────`,
            ...matSection.split('\n'),
            ``,
            `// ── MATERIAL_RULES ──────────────────────────────────────────`,
            ...rulesSection.split('\n'),
            ``,
            `// ── Apply materials ─────────────────────────────────────────`,
            ...generateApplyLoop().split('\n'),
            ``,
            `// ── Find LED meshes (replaces emissive-scan in viewer.html) ─`,
            ...generateLedDetection().split('\n'),
            ``,
            ...generateCameraCode().split('\n'),
        ];

        pre.innerHTML = allLines.map(hlLine).join('\n');
    }

    function generateMaterialsJs() {
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

        // Derive LED_MAX_INTENSITY from the ledMat emissiveIntensity value
        const ledIntensity = matProps.ledMat?.emissiveIntensity ?? 7.7;

        return [
            `// materials.js — material definitions for Pipit's 3D viewer`,
            `//`,
            `// Generated by tools/material-mapper.html — do not edit the section`,
            `// between the ▼▼▼ / ▲▲▲ markers by hand; re-export from the mapper instead.`,
            ``,
            `import * as THREE from 'three';`,
            ``,
            `// Max emissive intensity — keep in sync with KHR_materials_emissive_strength in Uguisu.glb.`,
            `export const LED_MAX_INTENSITY = ${ledIntensity};`,
            ``,
            `// ▼▼▼ START — generated by Material Mapper ▼▼▼`,
            matSection,
            ``,
            rulesSection,
            `// ▲▲▲ END ▲▲▲`,
            ``,
            `export { MATERIAL_RULES };`,
            ``,
        ].join('\n');
    }

    // ─────────────────────────────────────────────────────────────
    // Public API — return methods used by app.js
    // ─────────────────────────────────────────────────────────────
    return {
        // Getters / state access
        getMatProps:     () => matProps,
        getMAT_OBJ:      () => MAT_OBJ,
        getMAT_SCHEMA:   () => MAT_SCHEMA,
        getMAT_CLASS:    () => MAT_CLASS,

        // Material property updates
        setProp,

        // Part selection
        selectPart,
        selectMesh,
        clearSelection,
        selectAllVisible,
        syncSelectionEditor,
        setVisibility,
        syncShowAllBtn,
        clearOutlines,

        // UI building
        buildEditor,
        buildPartsUI,

        // Material application
        applyMaterials,
        guessKey,

        // Code generation
        generateMatDef,
        generateApplyLoop,
        generateLedDetection,
        generateMaterialsJs,
        updateCode,

        // Utilities
        updatePartCount: _updatePartCount,
    };
};
