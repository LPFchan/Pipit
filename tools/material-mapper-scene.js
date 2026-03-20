'use strict';

// Classic script module (no ESM import/export) so file:// opening remains compatible.
window.MaterialMapperSceneModule = function MaterialMapperSceneModule({
    THREE,
    renderer,
    scene,
    keyLight,
    fillLight,
    rimLight,
    ambientLight,
    groundMesh,
    envTexture,
    bloomPass,
    ssaoPass,
    postGradePass,
    saveState,
    requestRender,
}) {
    const PRESET_STORAGE_KEY = 'material-mapper-scene-presets-v1';

    function cloneState(value) {
        return JSON.parse(JSON.stringify(value));
    }

    function mergeStateInto(target, source) {
        for (const [key, val] of Object.entries(source || {})) {
            if (!(key in target) || !val || typeof val !== 'object') continue;
            Object.assign(target[key], val);
        }
    }

    const DEFAULT_SCENE_STATE = {
        renderer: { toneMap: 'ACES', output: 'sRGB', physicallyCorrect: true },
        bg:     { style: 'gradient', color1: '#1c1e28', color2: '#09090c', gradType: 'radial', solidColor: '#070910' },
        env:    {
            enabled: true,
            useAsBackground: false,
            intensity: 1.0,
            rotX: 0,
            rotY: 0,
            rotZ: 0,
            bgBlurriness: 0,
            bgIntensity: 1.0,
        },
        tm:     { exposure: 0.95 },
        key:    { color: '#fff8f0', intensity: 2.0, px: 1.5, py: 2.5, pz: 2.0, shadows: true },
        shadow: {
            type: 'PCFSoft',
            mapSize: 1024,
            radius: 8.0,
            bias: -0.0005,
            near: 0.1,
            far: 10,
            left: -2,
            right: 2,
            top: 2,
            bottom: -2,
        },
        fill:   { color: '#b0c8ff', intensity: 0.55, px: -2, py: 1, pz: -1.5 },
        rim:    { color: '#dde8ff', intensity: 0.45, px: 0, py: -1, pz: -2 },
        amb:    { color: '#ffffff', intensity: 0.1 },
        ground: { visible: true, opacity: 0.38, radius: 1.8 },
        post: {
            bloomEnabled: false,
            bloomStrength: 0.35,
            bloomRadius: 0.25,
            bloomThreshold: 0.72,
            ssaoEnabled: false,
            ssaoKernel: 16,
            ssaoMin: 0.005,
            ssaoMax: 0.18,
            vignetteEnabled: false,
            vignetteOffset: 1.0,
            vignetteDarkness: 1.25,
            gradeEnabled: false,
            gradeSaturation: 1.0,
            gradeContrast: 1.0,
            gradeBrightness: 0.0,
        },
    };

    function buildDefaultLightPreset() {
        const preset = cloneState(DEFAULT_SCENE_STATE);
        preset.bg.style = 'gradient';
        preset.bg.gradType = 'linear';
        preset.bg.color1 = '#f2f6fb';
        preset.bg.color2 = '#ffffff';
        preset.bg.solidColor = '#ffffff';
        preset.env.enabled = true;
        preset.env.useAsBackground = false;
        preset.env.intensity = 0.9;
        preset.env.bgBlurriness = 0;
        preset.env.bgIntensity = 1;
        preset.tm.exposure = 1.15;
        preset.key.color = '#fff8f0';
        preset.key.intensity = 2.7;
        preset.key.px = 1.7;
        preset.key.py = 2.8;
        preset.key.pz = 2.2;
        preset.key.shadows = true;
        preset.shadow.type = 'PCFSoft';
        preset.shadow.mapSize = 1024;
        preset.shadow.radius = 7.5;
        preset.fill.color = '#d7e6ff';
        preset.fill.intensity = 0.95;
        preset.fill.px = -2.2;
        preset.fill.py = 1.2;
        preset.fill.pz = -1.4;
        preset.rim.color = '#ffffff';
        preset.rim.intensity = 0.22;
        preset.rim.py = 0.2;
        preset.rim.pz = -1.3;
        preset.amb.intensity = 0.32;
        preset.ground.visible = true;
        preset.ground.opacity = 0.16;
        preset.post.bloomEnabled = false;
        preset.post.ssaoEnabled = false;
        preset.post.vignetteEnabled = false;
        preset.post.gradeEnabled = false;
        return preset;
    }

    function buildDefaultPresetStore() {
        return {
            light: { state: buildDefaultLightPreset(), updatedAt: null },
            dark: { state: cloneState(DEFAULT_SCENE_STATE), updatedAt: null },
        };
    }

    function loadPresetStore() {
        const defaults = buildDefaultPresetStore();
        try {
            const raw = JSON.parse(localStorage.getItem(PRESET_STORAGE_KEY) || 'null');
            if (!raw || typeof raw !== 'object') return defaults;

            for (const slotKey of ['light', 'dark']) {
                const savedSlot = raw[slotKey];
                if (!savedSlot || typeof savedSlot !== 'object') continue;
                if (savedSlot.state && typeof savedSlot.state === 'object') {
                    mergeStateInto(defaults[slotKey].state, savedSlot.state);
                }
                if (Number.isFinite(savedSlot.updatedAt)) {
                    defaults[slotKey].updatedAt = savedSlot.updatedAt;
                }
            }
        } catch (error) {
            console.warn('[Material Mapper] Scene preset restore failed', error);
        }
        return defaults;
    }

    function persistPresetStore() {
        try {
            localStorage.setItem(PRESET_STORAGE_KEY, JSON.stringify(presetStore));
        } catch (error) {
            console.warn('[Material Mapper] Scene preset save failed', error);
        }
    }

    const sceneState = cloneState(DEFAULT_SCENE_STATE);
    let presetStore = loadPresetStore();

    function captureSceneSnapshot() {
        return cloneState(sceneState);
    }

    function formatPresetTimestamp(timestamp) {
        try {
            return new Date(timestamp).toLocaleString([], {
                month: 'short',
                day: 'numeric',
                hour: 'numeric',
                minute: '2-digit',
            });
        } catch (_error) {
            return 'Saved';
        }
    }

    function getCurrentPresetSlot() {
        const current = JSON.stringify(captureSceneSnapshot());
        for (const slotKey of ['light', 'dark']) {
            if (JSON.stringify(presetStore[slotKey].state) === current) return slotKey;
        }
        return null;
    }

    function presetStatusLabel(slotKey, isActive) {
        const slot = presetStore[slotKey];
        const segments = [];
        if (isActive) segments.push('Active');
        segments.push(slot.updatedAt ? `Saved ${formatPresetTimestamp(slot.updatedAt)}` : 'Built-in');
        return segments.join(' · ');
    }

    function syncPresetControls() {
        const activeSlot = getCurrentPresetSlot();
        for (const slotKey of ['light', 'dark']) {
            const isActive = activeSlot === slotKey;
            const card = document.querySelector(`[data-scene-preset="${slotKey}"]`);
            const applyBtn = document.getElementById(`sp-apply-${slotKey}-btn`);
            const status = document.getElementById(`sp-preset-${slotKey}-status`);
            if (card) card.classList.toggle('active', isActive);
            if (applyBtn) {
                applyBtn.classList.toggle('active', isActive);
                applyBtn.setAttribute('aria-pressed', isActive ? 'true' : 'false');
            }
            if (status) status.textContent = presetStatusLabel(slotKey, isActive);
        }
    }

    function persistSceneChanges() {
        saveState();
        syncPresetControls();
    }

    function saveScenePreset(slotKey) {
        if (!presetStore[slotKey]) return;
        presetStore[slotKey] = {
            state: captureSceneSnapshot(),
            updatedAt: Date.now(),
        };
        persistPresetStore();
        syncPresetControls();
    }

    function applyScenePreset(slotKey) {
        const slot = presetStore[slotKey];
        if (!slot?.state) return;
        mergeStateInto(sceneState, slot.state);
        syncScenePanel();
        applyAll();
        persistSceneChanges();
    }

    function applyRendererSettings() {
        const r = sceneState.renderer;
        const tmMap = {
            No: THREE.NoToneMapping,
            Linear: THREE.LinearToneMapping,
            Reinhard: THREE.ReinhardToneMapping,
            Cineon: THREE.CineonToneMapping,
            ACES: THREE.ACESFilmicToneMapping,
        };
        renderer.toneMapping = tmMap[r.toneMap] ?? THREE.ACESFilmicToneMapping;
        renderer.outputColorSpace = r.output === 'Linear' ? THREE.LinearSRGBColorSpace : THREE.SRGBColorSpace;
        renderer.physicallyCorrectLights = !!r.physicallyCorrect;
        renderer.toneMappingExposure = sceneState.tm.exposure;
        requestRender?.();
    }

    function applyBackground() {
        const s  = sceneState.bg;
        const vp = document.getElementById('viewer-pane');
        if (sceneState.env.useAsBackground && sceneState.env.enabled) {
            vp.style.background = '#000000';
        } else if (s.style === 'gradient') {
            vp.style.background = s.gradType === 'radial'
                ? `radial-gradient(ellipse at 50% 38%, ${s.color1} 0%, ${s.color2} 100%)`
                : `linear-gradient(180deg, ${s.color1} 0%, ${s.color2} 100%)`;
        } else {
            vp.style.background = s.solidColor;
        }
        const g = s.style === 'gradient';
        const bgColor1Row = document.getElementById('sp-bg-color1-row');
        const bgColor2Row = document.getElementById('sp-bg-color2-row');
        const bgTypeRow = document.getElementById('sp-bg-type-row');
        const bgSolidRow = document.getElementById('sp-bg-solid-row');
        if (bgColor1Row) bgColor1Row.style.display = g ? '' : 'none';
        if (bgColor2Row) bgColor2Row.style.display = g ? '' : 'none';
        if (bgTypeRow) bgTypeRow.style.display = g ? '' : 'none';
        if (bgSolidRow) bgSolidRow.style.display = g ? 'none' : '';
        requestRender?.();
    }

    function applyEnv() {
        const e = sceneState.env;
        scene.environment          = e.enabled ? envTexture : null;
        scene.environmentIntensity = e.intensity;

        const rotX = THREE.MathUtils.degToRad(e.rotX);
        const rotY = THREE.MathUtils.degToRad(e.rotY);
        const rotZ = THREE.MathUtils.degToRad(e.rotZ);
        if (scene.environmentRotation) scene.environmentRotation.set(rotX, rotY, rotZ);

        scene.background = (e.enabled && e.useAsBackground) ? envTexture : null;
        if (scene.backgroundRotation) scene.backgroundRotation.set(rotX, rotY, rotZ);
        scene.backgroundBlurriness = (e.enabled && e.useAsBackground) ? e.bgBlurriness : 0;
        scene.backgroundIntensity  = (e.enabled && e.useAsBackground) ? e.bgIntensity  : 1;
        requestRender?.();
    }

    function applyToneMapping() {
        renderer.toneMappingExposure = sceneState.tm.exposure;
        requestRender?.();
    }

    function applyKeyLight() {
        const s = sceneState.key;
        const sh = sceneState.shadow;
        keyLight.color.set(s.color);
        keyLight.intensity = s.intensity;
        keyLight.position.set(s.px, s.py, s.pz);
        keyLight.castShadow = s.shadows;
        keyLight.shadow.mapSize.setScalar(Math.round(sh.mapSize));
        keyLight.shadow.radius = sh.radius;
        keyLight.shadow.bias   = sh.bias;
        keyLight.shadow.camera.near   = sh.near;
        keyLight.shadow.camera.far    = sh.far;
        keyLight.shadow.camera.left   = sh.left;
        keyLight.shadow.camera.right  = sh.right;
        keyLight.shadow.camera.top    = sh.top;
        keyLight.shadow.camera.bottom = sh.bottom;
        keyLight.shadow.camera.updateProjectionMatrix();

        const typeMap = {
            PCF: THREE.PCFShadowMap,
            PCFSoft: THREE.PCFSoftShadowMap,
            VSM: THREE.VSMShadowMap,
        };
        renderer.shadowMap.type = typeMap[sh.type] ?? THREE.PCFSoftShadowMap;
        renderer.shadowMap.needsUpdate = true;
        keyLight.shadow.needsUpdate = true;
        requestRender?.();
    }

    function applyFillLight() {
        fillLight.color.set(sceneState.fill.color);
        fillLight.intensity = sceneState.fill.intensity;
        fillLight.position.set(sceneState.fill.px, sceneState.fill.py, sceneState.fill.pz);
        requestRender?.();
    }

    function applyRimLight() {
        rimLight.color.set(sceneState.rim.color);
        rimLight.intensity = sceneState.rim.intensity;
        rimLight.position.set(sceneState.rim.px, sceneState.rim.py, sceneState.rim.pz);
        requestRender?.();
    }

    function applyAmbient() {
        ambientLight.color.set(sceneState.amb.color);
        ambientLight.intensity = sceneState.amb.intensity;
        requestRender?.();
    }

    function applyGround() {
        groundMesh.visible = sceneState.ground.visible;
        groundMesh.material.opacity = sceneState.ground.opacity;
        groundMesh.scale.setScalar(sceneState.ground.radius / 1.8);
        groundMesh.material.needsUpdate = true;
        requestRender?.();
    }

    function applyPostFx() {
        const p = sceneState.post;
        bloomPass.enabled = !!p.bloomEnabled;
        bloomPass.strength = p.bloomStrength;
        bloomPass.radius = p.bloomRadius;
        bloomPass.threshold = p.bloomThreshold;

        ssaoPass.enabled = !!p.ssaoEnabled;
        ssaoPass.kernelRadius = p.ssaoKernel;
        ssaoPass.minDistance = p.ssaoMin;
        ssaoPass.maxDistance = p.ssaoMax;

        postGradePass.enabled = !!(p.vignetteEnabled || p.gradeEnabled);
        postGradePass.uniforms.gradeEnabled.value = p.gradeEnabled ? 1 : 0;
        postGradePass.uniforms.saturation.value = p.gradeSaturation;
        postGradePass.uniforms.contrast.value = p.gradeContrast;
        postGradePass.uniforms.brightness.value = p.gradeBrightness;
        postGradePass.uniforms.vignetteEnabled.value = p.vignetteEnabled ? 1 : 0;
        postGradePass.uniforms.vignetteOffset.value = p.vignetteOffset;
        postGradePass.uniforms.vignetteDarkness.value = p.vignetteDarkness;
        requestRender?.();
    }

    function applyAll() {
        applyRendererSettings();
        applyBackground();
        applyEnv();
        applyToneMapping();
        applyKeyLight();
        applyFillLight();
        applyRimLight();
        applyAmbient();
        applyGround();
        applyPostFx();
    }

    function syncScenePanel() {
        const s   = sceneState;
        const setV  = (id, v) => { const el = document.getElementById(id); if (el) el.value       = v; };
        const setCk = (id, v) => { const el = document.getElementById(id); if (el) el.checked     = v; };
        const setTx = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = v; };
        setV('sp-renderer-tone-map', s.renderer.toneMap);
        setV('sp-renderer-output', s.renderer.output);
        setCk('sp-renderer-phys', s.renderer.physicallyCorrect);
        setV('sp-bg-style',     s.bg.style);     setV('sp-bg-grad-type',  s.bg.gradType);
        setV('sp-bg-color1',    s.bg.color1);    setTx('sp-bg-color1-hex', s.bg.color1);
        setV('sp-bg-color2',    s.bg.color2);    setTx('sp-bg-color2-hex', s.bg.color2);
        setV('sp-bg-solid',     s.bg.solidColor); setTx('sp-bg-solid-hex', s.bg.solidColor);
        setCk('sp-env-enabled', s.env.enabled);
        setCk('sp-env-as-bg', s.env.useAsBackground);
        setV('sp-env-intensity',     s.env.intensity);  setV('sp-env-intensity-num',  s.env.intensity);
        setV('sp-env-rot-x', s.env.rotX); setV('sp-env-rot-y', s.env.rotY); setV('sp-env-rot-z', s.env.rotZ);
        setV('sp-env-bg-blur', s.env.bgBlurriness); setV('sp-env-bg-blur-num', s.env.bgBlurriness);
        setV('sp-env-bg-intensity', s.env.bgIntensity); setV('sp-env-bg-intensity-num', s.env.bgIntensity);
        setV('sp-tm-exposure',       s.tm.exposure);    setV('sp-tm-exposure-num',    s.tm.exposure);
        setV('sp-key-color',         s.key.color);      setTx('sp-key-color-hex',     s.key.color);
        setV('sp-key-intensity',     s.key.intensity);  setV('sp-key-intensity-num',  s.key.intensity);
        setV('sp-key-pos-x', s.key.px); setV('sp-key-pos-y', s.key.py); setV('sp-key-pos-z', s.key.pz);
        setCk('sp-key-shadows', s.key.shadows);
        setV('sp-shadow-type', s.shadow.type);
        setV('sp-key-shadow-map',      s.shadow.mapSize); setV('sp-key-shadow-map-num',      s.shadow.mapSize);
        setV('sp-key-shadow-radius',   s.shadow.radius);  setV('sp-key-shadow-radius-num',   s.shadow.radius);
        setV('sp-key-shadow-bias',     s.shadow.bias);    setV('sp-key-shadow-bias-num',     s.shadow.bias);
        setV('sp-key-shadow-near', s.shadow.near); setV('sp-key-shadow-far', s.shadow.far);
        setV('sp-key-shadow-left', s.shadow.left); setV('sp-key-shadow-right', s.shadow.right);
        setV('sp-key-shadow-top', s.shadow.top); setV('sp-key-shadow-bottom', s.shadow.bottom);
        setV('sp-fill-color',        s.fill.color);     setTx('sp-fill-color-hex',    s.fill.color);
        setV('sp-fill-intensity',    s.fill.intensity); setV('sp-fill-intensity-num', s.fill.intensity);
        setV('sp-fill-pos-x', s.fill.px); setV('sp-fill-pos-y', s.fill.py); setV('sp-fill-pos-z', s.fill.pz);
        setV('sp-rim-color',         s.rim.color);      setTx('sp-rim-color-hex',     s.rim.color);
        setV('sp-rim-intensity',     s.rim.intensity);  setV('sp-rim-intensity-num',  s.rim.intensity);
        setV('sp-rim-pos-x', s.rim.px); setV('sp-rim-pos-y', s.rim.py); setV('sp-rim-pos-z', s.rim.pz);
        setV('sp-amb-color',         s.amb.color);      setTx('sp-amb-color-hex',     s.amb.color);
        setV('sp-amb-intensity',     s.amb.intensity);  setV('sp-amb-intensity-num',  s.amb.intensity);
        setCk('sp-ground-visible', s.ground.visible);
        setV('sp-ground-opacity',    s.ground.opacity); setV('sp-ground-opacity-num', s.ground.opacity);
        setV('sp-ground-radius', s.ground.radius); setV('sp-ground-radius-num', s.ground.radius);

        setCk('sp-post-bloom-enabled', s.post.bloomEnabled);
        setV('sp-post-bloom-strength', s.post.bloomStrength); setV('sp-post-bloom-strength-num', s.post.bloomStrength);
        setV('sp-post-bloom-radius', s.post.bloomRadius); setV('sp-post-bloom-radius-num', s.post.bloomRadius);
        setV('sp-post-bloom-threshold', s.post.bloomThreshold); setV('sp-post-bloom-threshold-num', s.post.bloomThreshold);
        setCk('sp-post-ssao-enabled', s.post.ssaoEnabled);
        setV('sp-post-ssao-kernel', s.post.ssaoKernel); setV('sp-post-ssao-kernel-num', s.post.ssaoKernel);
        setV('sp-post-ssao-min', s.post.ssaoMin); setV('sp-post-ssao-min-num', s.post.ssaoMin);
        setV('sp-post-ssao-max', s.post.ssaoMax); setV('sp-post-ssao-max-num', s.post.ssaoMax);
        setCk('sp-post-vig-enabled', s.post.vignetteEnabled);
        setV('sp-post-vig-offset', s.post.vignetteOffset); setV('sp-post-vig-offset-num', s.post.vignetteOffset);
        setV('sp-post-vig-darkness', s.post.vignetteDarkness); setV('sp-post-vig-darkness-num', s.post.vignetteDarkness);
        setCk('sp-post-grade-enabled', s.post.gradeEnabled);
        setV('sp-post-grade-sat', s.post.gradeSaturation); setV('sp-post-grade-sat-num', s.post.gradeSaturation);
        setV('sp-post-grade-contrast', s.post.gradeContrast); setV('sp-post-grade-contrast-num', s.post.gradeContrast);
        setV('sp-post-grade-bright', s.post.gradeBrightness); setV('sp-post-grade-bright-num', s.post.gradeBrightness);
        syncPresetControls();
    }

    function numVal(id, fallback) {
        const input = document.getElementById(id);
        if (!input) return fallback;
        const n = parseFloat(input.value);
        return Number.isFinite(n) ? n : fallback;
    }

    function bindIfPresent(id, eventName, handler) {
        const el = document.getElementById(id);
        if (!el) return false;
        el.addEventListener(eventName, handler);
        return true;
    }

    function spNum(sliderId, numId, stateKey, field, applyFn) {
        const sl = document.getElementById(sliderId);
        const nm = document.getElementById(numId);
        if (!sl || !nm) return;
        const set = v => {
            const n = parseFloat(v) || 0;
            sl.value = n; nm.value = n;
            sceneState[stateKey][field] = n;
            applyFn();
            persistSceneChanges();
        };
        sl.addEventListener('input',  () => set(sl.value));
        nm.addEventListener('change', () => set(nm.value));
    }

    function spColor(pickerId, hexId, stateKey, field, applyFn) {
        const pk = document.getElementById(pickerId);
        const hx = document.getElementById(hexId);
        if (!pk || !hx) return;
        pk.addEventListener('input', () => {
            hx.textContent = pk.value;
            sceneState[stateKey][field] = pk.value;
            applyFn();
            persistSceneChanges();
        });
    }

    function bindUI() {
        bindIfPresent('sp-apply-light-btn', 'click', () => applyScenePreset('light'));
        bindIfPresent('sp-save-light-btn', 'click', () => saveScenePreset('light'));
        bindIfPresent('sp-apply-dark-btn', 'click', () => applyScenePreset('dark'));
        bindIfPresent('sp-save-dark-btn', 'click', () => saveScenePreset('dark'));

        bindIfPresent('sp-renderer-tone-map', 'change', e => {
            sceneState.renderer.toneMap = e.target.value;
            applyRendererSettings();
            persistSceneChanges();
        });
        bindIfPresent('sp-renderer-output', 'change', e => {
            sceneState.renderer.output = e.target.value;
            applyRendererSettings();
            persistSceneChanges();
        });
        bindIfPresent('sp-renderer-phys', 'change', e => {
            sceneState.renderer.physicallyCorrect = e.target.checked;
            applyRendererSettings();
            persistSceneChanges();
        });

        bindIfPresent('sp-bg-style', 'change', e => {
            sceneState.bg.style = e.target.value; applyBackground(); persistSceneChanges();
        });
        bindIfPresent('sp-bg-grad-type', 'change', e => {
            sceneState.bg.gradType = e.target.value; applyBackground(); persistSceneChanges();
        });
        spColor('sp-bg-color1', 'sp-bg-color1-hex', 'bg', 'color1',     applyBackground);
        spColor('sp-bg-color2', 'sp-bg-color2-hex', 'bg', 'color2',     applyBackground);
        spColor('sp-bg-solid',  'sp-bg-solid-hex',  'bg', 'solidColor', applyBackground);

        bindIfPresent('sp-env-enabled', 'change', e => {
            sceneState.env.enabled = e.target.checked; applyEnv(); applyBackground(); persistSceneChanges();
        });
        bindIfPresent('sp-env-as-bg', 'change', e => {
            sceneState.env.useAsBackground = e.target.checked; applyEnv(); applyBackground(); persistSceneChanges();
        });
        spNum('sp-env-intensity', 'sp-env-intensity-num', 'env', 'intensity', applyEnv);
        spNum('sp-env-bg-blur', 'sp-env-bg-blur-num', 'env', 'bgBlurriness', applyEnv);
        spNum('sp-env-bg-intensity', 'sp-env-bg-intensity-num', 'env', 'bgIntensity', applyEnv);
        ['sp-env-rot-x', 'sp-env-rot-y', 'sp-env-rot-z'].forEach((id) => {
            bindIfPresent(id, 'change', () => {
                sceneState.env.rotX = numVal('sp-env-rot-x', 0);
                sceneState.env.rotY = numVal('sp-env-rot-y', 0);
                sceneState.env.rotZ = numVal('sp-env-rot-z', 0);
                applyEnv();
                persistSceneChanges();
            });
        });

        spNum('sp-tm-exposure', 'sp-tm-exposure-num', 'tm', 'exposure', () => {
            applyRendererSettings();
            applyToneMapping();
        });

        spColor('sp-key-color', 'sp-key-color-hex', 'key', 'color', applyKeyLight);
        spNum('sp-key-intensity', 'sp-key-intensity-num', 'key', 'intensity', applyKeyLight);
        spNum('sp-key-shadow-map', 'sp-key-shadow-map-num', 'shadow', 'mapSize', applyKeyLight);
        spNum('sp-key-shadow-radius', 'sp-key-shadow-radius-num', 'shadow', 'radius', applyKeyLight);
        spNum('sp-key-shadow-bias', 'sp-key-shadow-bias-num', 'shadow', 'bias', applyKeyLight);
        bindIfPresent('sp-shadow-type', 'change', e => {
            sceneState.shadow.type = e.target.value; applyKeyLight(); persistSceneChanges();
        });
        bindIfPresent('sp-key-shadows', 'change', e => {
            sceneState.key.shadows = e.target.checked; applyKeyLight(); persistSceneChanges();
        });
        ['sp-key-pos-x', 'sp-key-pos-y', 'sp-key-pos-z'].forEach((id) => {
            bindIfPresent(id, 'change', () => {
                sceneState.key.px = numVal('sp-key-pos-x', 1.5);
                sceneState.key.py = numVal('sp-key-pos-y', 2.5);
                sceneState.key.pz = numVal('sp-key-pos-z', 2.0);
                applyKeyLight(); persistSceneChanges();
            });
        });
        ['sp-key-shadow-near', 'sp-key-shadow-far', 'sp-key-shadow-left', 'sp-key-shadow-right', 'sp-key-shadow-top', 'sp-key-shadow-bottom'].forEach((id) => {
            bindIfPresent(id, 'change', () => {
                sceneState.shadow.near = numVal('sp-key-shadow-near', 0.1);
                sceneState.shadow.far = numVal('sp-key-shadow-far', 10);
                sceneState.shadow.left = numVal('sp-key-shadow-left', -2);
                sceneState.shadow.right = numVal('sp-key-shadow-right', 2);
                sceneState.shadow.top = numVal('sp-key-shadow-top', 2);
                sceneState.shadow.bottom = numVal('sp-key-shadow-bottom', -2);
                applyKeyLight();
                persistSceneChanges();
            });
        });

        spColor('sp-fill-color', 'sp-fill-color-hex', 'fill', 'color', applyFillLight);
        spNum('sp-fill-intensity', 'sp-fill-intensity-num', 'fill', 'intensity', applyFillLight);
        ['sp-fill-pos-x', 'sp-fill-pos-y', 'sp-fill-pos-z'].forEach((id) => {
            bindIfPresent(id, 'change', () => {
                sceneState.fill.px = numVal('sp-fill-pos-x', -2);
                sceneState.fill.py = numVal('sp-fill-pos-y', 1);
                sceneState.fill.pz = numVal('sp-fill-pos-z', -1.5);
                applyFillLight(); persistSceneChanges();
            });
        });

        spColor('sp-rim-color', 'sp-rim-color-hex', 'rim', 'color', applyRimLight);
        spNum('sp-rim-intensity', 'sp-rim-intensity-num', 'rim', 'intensity', applyRimLight);
        ['sp-rim-pos-x', 'sp-rim-pos-y', 'sp-rim-pos-z'].forEach((id) => {
            bindIfPresent(id, 'change', () => {
                sceneState.rim.px = numVal('sp-rim-pos-x', 0);
                sceneState.rim.py = numVal('sp-rim-pos-y', -1);
                sceneState.rim.pz = numVal('sp-rim-pos-z', -2);
                applyRimLight(); persistSceneChanges();
            });
        });

        spColor('sp-amb-color', 'sp-amb-color-hex', 'amb', 'color', applyAmbient);
        spNum('sp-amb-intensity', 'sp-amb-intensity-num', 'amb', 'intensity', applyAmbient);

        bindIfPresent('sp-ground-visible', 'change', e => {
            sceneState.ground.visible = e.target.checked; applyGround(); persistSceneChanges();
        });
        spNum('sp-ground-opacity', 'sp-ground-opacity-num', 'ground', 'opacity', applyGround);
        spNum('sp-ground-radius', 'sp-ground-radius-num', 'ground', 'radius', applyGround);

        bindIfPresent('sp-post-bloom-enabled', 'change', e => {
            sceneState.post.bloomEnabled = e.target.checked; applyPostFx(); persistSceneChanges();
        });
        spNum('sp-post-bloom-strength', 'sp-post-bloom-strength-num', 'post', 'bloomStrength', applyPostFx);
        spNum('sp-post-bloom-radius', 'sp-post-bloom-radius-num', 'post', 'bloomRadius', applyPostFx);
        spNum('sp-post-bloom-threshold', 'sp-post-bloom-threshold-num', 'post', 'bloomThreshold', applyPostFx);

        bindIfPresent('sp-post-ssao-enabled', 'change', e => {
            sceneState.post.ssaoEnabled = e.target.checked; applyPostFx(); persistSceneChanges();
        });
        spNum('sp-post-ssao-kernel', 'sp-post-ssao-kernel-num', 'post', 'ssaoKernel', applyPostFx);
        spNum('sp-post-ssao-min', 'sp-post-ssao-min-num', 'post', 'ssaoMin', applyPostFx);
        spNum('sp-post-ssao-max', 'sp-post-ssao-max-num', 'post', 'ssaoMax', applyPostFx);

        bindIfPresent('sp-post-vig-enabled', 'change', e => {
            sceneState.post.vignetteEnabled = e.target.checked; applyPostFx(); persistSceneChanges();
        });
        spNum('sp-post-vig-offset', 'sp-post-vig-offset-num', 'post', 'vignetteOffset', applyPostFx);
        spNum('sp-post-vig-darkness', 'sp-post-vig-darkness-num', 'post', 'vignetteDarkness', applyPostFx);

        bindIfPresent('sp-post-grade-enabled', 'change', e => {
            sceneState.post.gradeEnabled = e.target.checked; applyPostFx(); persistSceneChanges();
        });
        spNum('sp-post-grade-sat', 'sp-post-grade-sat-num', 'post', 'gradeSaturation', applyPostFx);
        spNum('sp-post-grade-contrast', 'sp-post-grade-contrast-num', 'post', 'gradeContrast', applyPostFx);
        spNum('sp-post-grade-bright', 'sp-post-grade-bright-num', 'post', 'gradeBrightness', applyPostFx);
    }

    function mergeState(savedSceneState) {
        mergeStateInto(sceneState, savedSceneState);
    }

    function buildViewerSceneExportPayload(sourceState) {
        const s = sourceState;
        const bodyBackground = s.bg.style === 'gradient'
            ? (s.bg.gradType === 'radial'
                ? `radial-gradient(ellipse at 50% 38%, ${s.bg.color1} 0%, ${s.bg.color2} 100%)`
                : `linear-gradient(180deg, ${s.bg.color1} 0%, ${s.bg.color2} 100%)`)
            : s.bg.solidColor;
        return {
            renderer: {
                toneMap: s.renderer.toneMap,
                output: s.renderer.output,
                physicallyCorrect: !!s.renderer.physicallyCorrect,
            },
            bodyBackground,
            env: {
                enabled: s.env.enabled,
                useAsBackground: s.env.useAsBackground,
                intensity: s.env.intensity,
                rotDeg: [s.env.rotX, s.env.rotY, s.env.rotZ],
                bgBlurriness: s.env.bgBlurriness,
                bgIntensity: s.env.bgIntensity,
                roomEnvBlur: 0.04,
            },
            tm: { exposure: s.tm.exposure },
            shadowMap: { enabled: true, type: s.shadow.type },
            key: {
                color: s.key.color,
                intensity: s.key.intensity,
                px: s.key.px,
                py: s.key.py,
                pz: s.key.pz,
                shadows: s.key.shadows,
            },
            shadow: {
                mapSize: s.shadow.mapSize,
                radius: s.shadow.radius,
                bias: s.shadow.bias,
                near: s.shadow.near,
                far: s.shadow.far,
                left: s.shadow.left,
                right: s.shadow.right,
                top: s.shadow.top,
                bottom: s.shadow.bottom,
            },
            fill: {
                color: s.fill.color,
                intensity: s.fill.intensity,
                px: s.fill.px,
                py: s.fill.py,
                pz: s.fill.pz,
            },
            rim: {
                color: s.rim.color,
                intensity: s.rim.intensity,
                px: s.rim.px,
                py: s.rim.py,
                pz: s.rim.pz,
            },
            amb: { color: s.amb.color, intensity: s.amb.intensity },
            ground: {
                visible: s.ground.visible,
                opacity: s.ground.opacity,
                radius: s.ground.radius,
                yPlaceholder: -0.52,
            },
            post: {
                bloomEnabled: s.post.bloomEnabled,
                bloomStrength: s.post.bloomStrength,
                bloomRadius: s.post.bloomRadius,
                bloomThreshold: s.post.bloomThreshold,
                ssaoEnabled: s.post.ssaoEnabled,
                ssaoKernel: s.post.ssaoKernel,
                ssaoMin: s.post.ssaoMin,
                ssaoMax: s.post.ssaoMax,
                vignetteEnabled: s.post.vignetteEnabled,
                vignetteOffset: s.post.vignetteOffset,
                vignetteDarkness: s.post.vignetteDarkness,
                gradeEnabled: s.post.gradeEnabled,
                gradeSaturation: s.post.gradeSaturation,
                gradeContrast: s.post.gradeContrast,
                gradeBrightness: s.post.gradeBrightness,
            },
        };
    }

    /** Plain object for export into assets/materials.js as VIEWER_SCENE. */
    function getViewerSceneExportPayload() {
        return buildViewerSceneExportPayload(sceneState);
    }

    function getViewerScenePresetExportPayload() {
        return {
            light: buildViewerSceneExportPayload(presetStore.light.state),
            dark: buildViewerSceneExportPayload(presetStore.dark.state),
        };
    }

    function generateSceneCode() {
        const s = sceneState;
        const presetPayload = getViewerScenePresetExportPayload();
        const activePresetSlot = getCurrentPresetSlot() ?? 'custom';
        const x = h => '0x' + h.replace('#', '');
        const f = n => (Math.round(n * 1000) / 1000).toString();
        const bgCss = s.bg.style === 'gradient'
            ? (s.bg.gradType === 'radial'
                ? `radial-gradient(ellipse at 50% 38%, ${s.bg.color1} 0%, ${s.bg.color2} 100%)`
                : `linear-gradient(180deg, ${s.bg.color1} 0%, ${s.bg.color2} 100%)`)
            : s.bg.solidColor;

        const toneMapLabel = ({ No: 'NoToneMapping', Linear: 'LinearToneMapping', Reinhard: 'ReinhardToneMapping', Cineon: 'CineonToneMapping', ACES: 'ACESFilmicToneMapping' }[s.renderer.toneMap] ?? 'ACESFilmicToneMapping');
        const shadowTypeLabel = ({ PCF: 'PCFShadowMap', PCFSoft: 'PCFSoftShadowMap', VSM: 'VSMShadowMap' }[s.shadow.type] ?? 'PCFSoftShadowMap');

        return [
            `// ─── CSS ────────────────────────────────────────────────────────────────────`,
            `// html, body { background: ${bgCss}; }`,
            `// (renderer setClearColor 0 alpha already keeps canvas transparent)`,
            ``,
            `// ─── Renderer ────────────────────────────────────────────────────────────────`,
            `renderer.toneMapping         = THREE.${toneMapLabel};`,
            `renderer.toneMappingExposure = ${f(s.tm.exposure)};`,
            `renderer.outputColorSpace    = THREE.${s.renderer.output === 'Linear' ? 'LinearSRGBColorSpace' : 'SRGBColorSpace'};`,
            `renderer.physicallyCorrectLights = ${s.renderer.physicallyCorrect};`,
            `renderer.setClearColor(0x000000, 0);`,
            `renderer.shadowMap.enabled = true;`,
            `renderer.shadowMap.type    = THREE.${shadowTypeLabel};`,
            ``,
            `// ─── IBL ─────────────────────────────────────────────────────────────────────`,
            `import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';`,
            `const pmremGenerator = new THREE.PMREMGenerator(renderer);`,
            `const roomEnv    = new RoomEnvironment();`,
            `const envTexture = pmremGenerator.fromScene(roomEnv, 0.04).texture;`,
            `scene.environment          = ${s.env.enabled ? 'envTexture' : 'null'};`,
            `scene.environmentIntensity = ${f(s.env.intensity)};`,
            `if (scene.environmentRotation) scene.environmentRotation.set(${f(THREE.MathUtils.degToRad(s.env.rotX))}, ${f(THREE.MathUtils.degToRad(s.env.rotY))}, ${f(THREE.MathUtils.degToRad(s.env.rotZ))});`,
            `scene.background = ${s.env.enabled && s.env.useAsBackground ? 'envTexture' : 'null'};`,
            `if (scene.backgroundRotation) scene.backgroundRotation.set(${f(THREE.MathUtils.degToRad(s.env.rotX))}, ${f(THREE.MathUtils.degToRad(s.env.rotY))}, ${f(THREE.MathUtils.degToRad(s.env.rotZ))});`,
            `scene.backgroundBlurriness = ${f(s.env.bgBlurriness)};`,
            `scene.backgroundIntensity  = ${f(s.env.bgIntensity)};`,
            `roomEnv.dispose(); pmremGenerator.dispose();`,
            ``,
            `// ─── Lights ──────────────────────────────────────────────────────────────────`,
            `const keyLight = new THREE.DirectionalLight(${x(s.key.color)}, ${f(s.key.intensity)});`,
            `keyLight.position.set(${f(s.key.px)}, ${f(s.key.py)}, ${f(s.key.pz)});`,
            `keyLight.castShadow = ${s.key.shadows};`,
            `keyLight.shadow.mapSize.setScalar(${Math.round(s.shadow.mapSize)});`,
            `keyLight.shadow.camera.near = ${f(s.shadow.near)}; keyLight.shadow.camera.far = ${f(s.shadow.far)};`,
            `keyLight.shadow.camera.left = ${f(s.shadow.left)};  keyLight.shadow.camera.right = ${f(s.shadow.right)};`,
            `keyLight.shadow.camera.top  = ${f(s.shadow.top)};  keyLight.shadow.camera.bottom = ${f(s.shadow.bottom)};`,
            `keyLight.shadow.radius = ${f(s.shadow.radius)}; keyLight.shadow.bias = ${s.shadow.bias.toFixed(4)};`,
            `scene.add(keyLight);`,
            `const fillLight = new THREE.DirectionalLight(${x(s.fill.color)}, ${f(s.fill.intensity)});`,
            `fillLight.position.set(${f(s.fill.px)}, ${f(s.fill.py)}, ${f(s.fill.pz)});`,
            `scene.add(fillLight);`,
            `const rimLight = new THREE.DirectionalLight(${x(s.rim.color)}, ${f(s.rim.intensity)});`,
            `rimLight.position.set(${f(s.rim.px)}, ${f(s.rim.py)}, ${f(s.rim.pz)});`,
            `scene.add(rimLight);`,
            `scene.add(new THREE.AmbientLight(${x(s.amb.color)}, ${f(s.amb.intensity)}));`,
            ``,
            `// ─── Shadow-catcher floor ────────────────────────────────────────────────────`,
            `const groundPlane = new THREE.Mesh(`,
            `    new THREE.CircleGeometry(${f(s.ground.radius)}, 64),`,
            `    new THREE.ShadowMaterial({ opacity: ${f(s.ground.opacity)}, transparent: true })`,
            `);`,
            `groundPlane.rotation.x = -Math.PI / 2;`,
            `groundPlane.position.y = -0.52;   // snapped to model bottom after load`,
            `groundPlane.receiveShadow = true;`,
            `${s.ground.visible ? '' : '// '}scene.add(groundPlane);`,
            ``,
            `// ─── Post FX ─────────────────────────────────────────────────────────────────`,
            `// bloom enabled: ${s.post.bloomEnabled}, strength: ${f(s.post.bloomStrength)}, radius: ${f(s.post.bloomRadius)}, threshold: ${f(s.post.bloomThreshold)}`,
            `// ssao enabled: ${s.post.ssaoEnabled}, kernel: ${f(s.post.ssaoKernel)}, minDistance: ${f(s.post.ssaoMin)}, maxDistance: ${f(s.post.ssaoMax)}`,
            `// vignette enabled: ${s.post.vignetteEnabled}, offset: ${f(s.post.vignetteOffset)}, darkness: ${f(s.post.vignetteDarkness)}`,
            `// color grade enabled: ${s.post.gradeEnabled}, sat: ${f(s.post.gradeSaturation)}, contrast: ${f(s.post.gradeContrast)}, bright: ${f(s.post.gradeBrightness)}`,
            ``,
            `// ─── In GLB load callback ────────────────────────────────────────────────────`,
            `rootModel.traverse(obj => {`,
            `    if (obj.isMesh) { obj.castShadow = true; obj.receiveShadow = true; }`,
            `});`,
            `const modelBox = new THREE.Box3().setFromObject(modelPivot);`,
            `groundPlane.position.y = modelBox.min.y - 0.008;`,
            ``,
            `// ─── Scene preset payloads ─────────────────────────────────────────────────`,
            `// active slot: ${activePresetSlot}`,
            `const VIEWER_SCENE = ${JSON.stringify(getViewerSceneExportPayload(), null, 4)};`,
            ``,
            `const VIEWER_SCENE_PRESETS = ${JSON.stringify(presetPayload, null, 4)};`,
        ].join('\n');
    }

    function init() {
        syncScenePanel();
        applyAll();
        bindUI();
        syncPresetControls();
    }

    return {
        init,
        getState: () => sceneState,
        mergeState,
        syncScenePanel,
        applyAll,
        generateSceneCode,
        getViewerSceneExportPayload,
        getViewerScenePresetExportPayload,
    };
};
