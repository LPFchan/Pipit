'use strict';

window.MaterialMapperCameraModule = function ({
    THREE,
    camera,
    orthoCamera,
    controls,
    groundMesh,
    saveState,
    requestRender,
    showToast,
    generateCameraCode,
    getLoadedModel,
    getIsOrtho,
    setIsOrtho,
}) {
    let initialized = false;
    let hudCollapsed = false;
    const FLOOR_EPSILON = 0.008;

    function getHudElements() {
        return {
            hud: document.getElementById('camera-hud'),
            toggleBtn: document.getElementById('camera-hud-toggle-btn'),
        };
    }

    function syncHudCollapsed() {
        const { hud, toggleBtn } = getHudElements();
        if (!hud || !toggleBtn) return;
        hud.classList.toggle('collapsed', hudCollapsed);
        toggleBtn.textContent = hudCollapsed ? '▸' : '▾';
        toggleBtn.setAttribute('aria-expanded', hudCollapsed ? 'false' : 'true');
        toggleBtn.title = hudCollapsed ? 'Expand camera panel' : 'Collapse camera panel';
    }

    function setHudCollapsed(nextCollapsed, persist = true) {
        hudCollapsed = !!nextCollapsed;
        syncHudCollapsed();
        if (persist) saveState();
    }

    function toggleHudCollapsed() {
        setHudCollapsed(!hudCollapsed, true);
    }

    function setHudXYZ(idX, idY, idZ, vec) {
        const f = (n) => (Math.round(n * 10000) / 10000).toString();
        const elX = document.getElementById(idX);
        const elY = document.getElementById(idY);
        const elZ = document.getElementById(idZ);
        if (!elX || !elY || !elZ) return;
        if (document.activeElement !== elX) elX.value = f(vec.x);
        if (document.activeElement !== elY) elY.value = f(vec.y);
        if (document.activeElement !== elZ) elZ.value = f(vec.z);
    }

    function setHudXYZDeg(idX, idY, idZ, euler) {
        const fD = (r) => (Math.round(THREE.MathUtils.radToDeg(r) * 10) / 10).toString();
        const elX = document.getElementById(idX);
        const elY = document.getElementById(idY);
        const elZ = document.getElementById(idZ);
        if (!elX || !elY || !elZ) return;
        if (document.activeElement !== elX) elX.value = fD(euler.x);
        if (document.activeElement !== elY) elY.value = fD(euler.y);
        if (document.activeElement !== elZ) elZ.value = fD(euler.z);
    }

    function updateCameraHUD() {
        setHudXYZ('hud-pos-x', 'hud-pos-y', 'hud-pos-z', camera.position);
        setHudXYZ('hud-tgt-x', 'hud-tgt-y', 'hud-tgt-z', controls.target);
        const loadedModel = getLoadedModel();
        if (loadedModel) setHudXYZDeg('hud-rot-x', 'hud-rot-y', 'hud-rot-z', loadedModel.rotation);
    }

    function getModelBounds() {
        const loadedModel = getLoadedModel();
        if (!loadedModel) return null;
        loadedModel.updateMatrixWorld(true);
        return new THREE.Box3().setFromObject(loadedModel);
    }

    function syncGroundToModel() {
        const box = getModelBounds();
        if (!box) return null;
        groundMesh.position.y = box.min.y - FLOOR_EPSILON;
        return box;
    }

    function syncOrbitTarget(options = {}) {
        const { preserveView = true, persist = false } = options;
        const box = getModelBounds();
        if (!box) return;
        const center = box.getCenter(new THREE.Vector3());
        if (preserveView) {
            const delta = center.clone().sub(controls.target);
            if (delta.lengthSq() > 0) camera.position.add(delta);
        }
        controls.target.copy(center);
        controls.update();
        updateCameraHUD();
        requestRender?.();
        if (persist) saveState();
    }

    function fitCameraToModel(persist = true) {
        const loadedModel = getLoadedModel();
        if (!loadedModel) return;
        const box = getModelBounds();
        if (!box) return;
        const size = box.getSize(new THREE.Vector3());
        const maxDim = Math.max(size.x, size.y, size.z) || 1;
        const fov = camera.fov;
        const dist = (maxDim * 0.5) / Math.tan(fov * Math.PI / 360) * 1.5;
        const center = box.getCenter(new THREE.Vector3());
        controls.target.copy(center);
        camera.position.set(center.x, center.y + maxDim * 0.08, center.z + dist);
        controls.update();
        updateCameraHUD();
        requestRender?.();
        if (persist) saveState();
    }

    function parseHudXYZ(idX, idY, idZ) {
        return {
            x: parseFloat(document.getElementById(idX).value) || 0,
            y: parseFloat(document.getElementById(idY).value) || 0,
            z: parseFloat(document.getElementById(idZ).value) || 0,
        };
    }

    function applyModelRotationDeg(x, y, z, persist = true) {
        const loadedModel = getLoadedModel();
        if (!loadedModel) return;
        loadedModel.rotation.set(
            THREE.MathUtils.degToRad(x),
            THREE.MathUtils.degToRad(y),
            THREE.MathUtils.degToRad(z)
        );
        setHudXYZDeg('hud-rot-x', 'hud-rot-y', 'hud-rot-z', loadedModel.rotation);
        syncOrbitTarget({ preserveView: true, persist: false });
        if (persist) saveState();
    }

    function nudgeModelRotation(axis, degStep) {
        const loadedModel = getLoadedModel();
        if (!loadedModel || !['x', 'y', 'z'].includes(axis)) return;
        const currentDeg = THREE.MathUtils.radToDeg(loadedModel.rotation[axis]);
        const next = {
            x: THREE.MathUtils.radToDeg(loadedModel.rotation.x),
            y: THREE.MathUtils.radToDeg(loadedModel.rotation.y),
            z: THREE.MathUtils.radToDeg(loadedModel.rotation.z),
        };
        next[axis] = currentDeg + degStep;
        applyModelRotationDeg(next.x, next.y, next.z, true);
    }

    function snapToFloor() {
        const loadedModel = getLoadedModel();
        if (!loadedModel) return;

        let box = getModelBounds();
        if (!box) return;
        const center = box.getCenter(new THREE.Vector3());
        loadedModel.position.x -= center.x;
        loadedModel.position.z -= center.z;

        box = getModelBounds();
        if (!box) return;
        loadedModel.position.y -= box.min.y;

        syncGroundToModel();
        syncOrbitTarget({ preserveView: true, persist: false });
        saveState();
        showToast('Snapped to floor & centered');
    }

    function syncOrthoButton() {
        const btn = document.getElementById('hud-ortho-btn');
        if (!btn) return;
        btn.classList.toggle('active', !!getIsOrtho());
    }

    function toggleOrtho() {
        setIsOrtho(!getIsOrtho());
        syncOrthoButton();
        requestRender?.();
        saveState();
    }

    const NUM_DRAG_PX_PER_STEP = 12;
    let numberDrag = null;

    function parseNumberStep(input) {
        const raw = input.getAttribute('step');
        if (!raw || raw === 'any') return 1;
        const n = parseFloat(raw);
        return Number.isFinite(n) && n > 0 ? n : 1;
    }

    function parseNumberBound(input, key) {
        const n = parseFloat(input[key]);
        return Number.isFinite(n) ? n : null;
    }

    function clampNumber(v, min, max) {
        if (min !== null) v = Math.max(min, v);
        if (max !== null) v = Math.min(max, v);
        return v;
    }

    function snapToStep(v, step, min) {
        const base = min ?? 0;
        const snapped = Math.round((v - base) / step) * step + base;
        return Number.parseFloat(snapped.toFixed(10));
    }

    function numberDecimals(step) {
        const s = String(step);
        const i = s.indexOf('.');
        return i === -1 ? 0 : Math.min(8, s.length - i - 1);
    }

    function formatDraggedNumber(v, step) {
        const decimals = numberDecimals(step);
        if (decimals <= 0) return String(Math.round(v));
        return v.toFixed(decimals).replace(/\.0+$/, '').replace(/(\.\d*?)0+$/, '$1');
    }

    function endNumberDrag(pointerId = null) {
        if (!numberDrag) return;
        if (pointerId !== null && numberDrag.pointerId !== pointerId) return;

        const wasDragging = numberDrag.dragging;
        const input = numberDrag.input;
        try {
            if (input.hasPointerCapture(numberDrag.pointerId)) {
                input.releasePointerCapture(numberDrag.pointerId);
            }
        } catch (_) {}

        numberDrag = null;
        document.body.classList.remove('num-dragging');

        if (wasDragging) {
            input.dataset.dragJustEnded = '1';
            setTimeout(() => { delete input.dataset.dragJustEnded; }, 0);
        }
    }

    function bindHudControls() {
        const bindIfPresent = (id, eventName, handler) => {
            const el = document.getElementById(id);
            if (!el) return false;
            el.addEventListener(eventName, handler);
            return true;
        };

        bindIfPresent('camera-hud-toggle-btn', 'click', toggleHudCollapsed);

        ['hud-pos-x', 'hud-pos-y', 'hud-pos-z'].forEach((id) => {
            document.getElementById(id).addEventListener('change', () => {
                const v = parseHudXYZ('hud-pos-x', 'hud-pos-y', 'hud-pos-z');
                camera.position.set(v.x, v.y, v.z);
                controls.update();
                requestRender?.();
                saveState();
            });
        });

        ['hud-tgt-x', 'hud-tgt-y', 'hud-tgt-z'].forEach((id) => {
            document.getElementById(id).addEventListener('change', () => {
                const v = parseHudXYZ('hud-tgt-x', 'hud-tgt-y', 'hud-tgt-z');
                controls.target.set(v.x, v.y, v.z);
                controls.update();
                requestRender?.();
                saveState();
            });
        });

        ['hud-rot-x', 'hud-rot-y', 'hud-rot-z'].forEach((id) => {
            document.getElementById(id).addEventListener('change', () => {
                if (!getLoadedModel()) return;
                const v = parseHudXYZ('hud-rot-x', 'hud-rot-y', 'hud-rot-z');
                applyModelRotationDeg(v.x, v.y, v.z, true);
            });
        });

        document.querySelectorAll('.hud-rot-step-btn').forEach((btn) => {
            btn.addEventListener('click', () => {
                const axis = btn.dataset.axis;
                const step = parseFloat(btn.dataset.step || '0');
                if (!Number.isFinite(step)) return;
                nudgeModelRotation(axis, step);
            });
        });

        const hudFovInput = document.getElementById('hud-fov');
        if (hudFovInput) {
            hudFovInput.value = camera.fov;
            hudFovInput.addEventListener('change', () => {
                const v = Math.max(5, Math.min(120, parseFloat(hudFovInput.value) || 38));
                hudFovInput.value = v;
                camera.fov = v;
                camera.updateProjectionMatrix();
                requestRender?.();
                saveState();
            });
        }

        bindIfPresent('hud-fit-btn', 'click', fitCameraToModel);
        bindIfPresent('hud-center-orbit-btn', 'click', () => syncOrbitTarget({ preserveView: true, persist: true }));
        bindIfPresent('hud-snap-btn', 'click', snapToFloor);
        bindIfPresent('hud-ortho-btn', 'click', toggleOrtho);
        bindIfPresent('hud-copy-cam-btn', 'click', () => {
            navigator.clipboard.writeText(generateCameraCode()).then(() => showToast('Camera code copied!'));
        });

        syncOrthoButton();
    }

    function bindNumberDrag() {
        document.addEventListener('pointerdown', (e) => {
            if (e.button !== 0) return;
            if (e.pointerType && e.pointerType !== 'mouse' && e.pointerType !== 'pen') return;

            const input = e.target.closest('input[type="number"]');
            if (!input || input.disabled || input.readOnly) return;

            const startValue = parseFloat(input.value);
            if (!Number.isFinite(startValue)) return;

            const step = parseNumberStep(input);
            const min = parseNumberBound(input, 'min');
            const max = parseNumberBound(input, 'max');

            numberDrag = {
                pointerId: e.pointerId,
                input,
                startX: e.clientX,
                startY: e.clientY,
                startValue,
                currentValue: startValue,
                step,
                min,
                max,
                dragging: false,
            };

            try { input.setPointerCapture(e.pointerId); } catch (_) {}
        }, true);

        document.addEventListener('pointermove', (e) => {
            if (!numberDrag || numberDrag.pointerId !== e.pointerId) return;

            const dx = e.clientX - numberDrag.startX;
            const dy = e.clientY - numberDrag.startY;
            const distSq = dx * dx + dy * dy;

            if (!numberDrag.dragging) {
                if (distSq < 16) return;
                numberDrag.dragging = true;
                numberDrag.input.blur();
                document.body.classList.add('num-dragging');
            }

            e.preventDefault();

            const speed = e.shiftKey ? 0.2 : (e.altKey ? 3 : 1);
            let next = numberDrag.startValue + (dx / NUM_DRAG_PX_PER_STEP) * numberDrag.step * speed;
            next = snapToStep(next, numberDrag.step, numberDrag.min);
            next = clampNumber(next, numberDrag.min, numberDrag.max);

            if (Math.abs(next - numberDrag.currentValue) < 1e-12) return;
            numberDrag.currentValue = next;

            numberDrag.input.value = formatDraggedNumber(next, numberDrag.step);
            numberDrag.input.dispatchEvent(new Event('input', { bubbles: true }));
            numberDrag.input.dispatchEvent(new Event('change', { bubbles: true }));
        }, { passive: false });

        document.addEventListener('pointerup', (e) => endNumberDrag(e.pointerId), true);
        document.addEventListener('pointercancel', (e) => endNumberDrag(e.pointerId), true);

        document.addEventListener('click', (e) => {
            const input = e.target.closest('input[type="number"]');
            if (!input || input.dataset.dragJustEnded !== '1') return;
            e.preventDefault();
            e.stopPropagation();
        }, true);
    }

    function init() {
        if (initialized) return;
        bindHudControls();
        bindNumberDrag();
        controls.addEventListener('end', saveState);
        syncHudCollapsed();
        initialized = true;
    }

    return {
        init,
        setHudXYZ,
        setHudXYZDeg,
        updateCameraHUD,
        syncOrbitTarget,
        fitCameraToModel,
        applyModelRotationDeg,
        syncGroundToModel,
        toggleOrtho,
        getHudState: () => ({ collapsed: hudCollapsed }),
        restoreHudState: (savedHudState) => {
            if (!savedHudState || typeof savedHudState.collapsed !== 'boolean') return;
            setHudCollapsed(savedHudState.collapsed, false);
        },
    };
};
