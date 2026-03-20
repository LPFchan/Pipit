'use strict';

window.MaterialMapperApp = async function ({ THREE, OrbitControls, GLTFLoader, GLTFExporter, RoomEnvironment, EffectComposer, RenderPass, UnrealBloomPass, SSAOPass, ShaderPass }) {
    // ─────────────────────────────────────────────────────────────
    // Renderer
    // ─────────────────────────────────────────────────────────────
    const container = document.getElementById('canvas-container');
    const renderer  = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.toneMapping         = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 0.95;
    renderer.shadowMap.enabled   = true;
    renderer.shadowMap.type      = THREE.PCFSoftShadowMap;
    container.appendChild(renderer.domElement);

    const scene  = new THREE.Scene();
    scene.background = null; // backdrop controlled by CSS on viewer-pane

    const camera = new THREE.PerspectiveCamera(38, 1, 0.0001, 1000);
    camera.position.set(0, 0, 1);

    const orthoCamera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.0001, 1000);
    let isOrtho = false;

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping   = true;
    controls.dampingFactor   = 0.06;
    controls.autoRotate      = false;
    controls.autoRotateSpeed = 0.7;

    let composer = null;
    let renderPass = null;
    let bloomPass = null;
    let ssaoPass = null;
    let postGradePass = null;

    function setRenderSize(w, h) {
        renderer.setSize(w, h);
        if (composer) composer.setSize(w, h);
        if (bloomPass && bloomPass.setSize) bloomPass.setSize(w, h);
        if (ssaoPass && ssaoPass.setSize) ssaoPass.setSize(w, h);
    }

    const PostGradeVignetteShader = {
        uniforms: {
            tDiffuse:         { value: null },
            gradeEnabled:     { value: 0 },
            saturation:       { value: 1.0 },
            contrast:         { value: 1.0 },
            brightness:       { value: 0.0 },
            vignetteEnabled:  { value: 0 },
            vignetteOffset:   { value: 1.0 },
            vignetteDarkness: { value: 1.25 },
        },
        vertexShader: `
            varying vec2 vUv;
            void main() {
                vUv = uv;
                gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
            }
        `,
        fragmentShader: `
            uniform sampler2D tDiffuse;
            uniform int gradeEnabled;
            uniform float saturation;
            uniform float contrast;
            uniform float brightness;
            uniform int vignetteEnabled;
            uniform float vignetteOffset;
            uniform float vignetteDarkness;
            varying vec2 vUv;
            void main() {
                vec4 c = texture2D(tDiffuse, vUv);
                if (gradeEnabled == 1) {
                    float l = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
                    c.rgb = mix(vec3(l), c.rgb, saturation);
                    c.rgb = (c.rgb - 0.5) * contrast + 0.5;
                    c.rgb += vec3(brightness);
                }
                if (vignetteEnabled == 1) {
                    vec2 uv = (vUv - vec2(0.5)) * vec2(vignetteOffset);
                    float vig = clamp(1.0 - dot(uv, uv) * vignetteDarkness, 0.0, 1.0);
                    c.rgb *= vig;
                }
                gl_FragColor = c;
            }
        `,
    };

    composer = new EffectComposer(renderer);
    renderPass = new RenderPass(scene, camera);
    composer.addPass(renderPass);

    bloomPass = new UnrealBloomPass(new THREE.Vector2(1, 1), 0.35, 0.25, 0.72);
    bloomPass.enabled = false;
    composer.addPass(bloomPass);

    ssaoPass = new SSAOPass(scene, camera, 1, 1);
    ssaoPass.enabled = false;
    ssaoPass.kernelRadius = 16;
    ssaoPass.minDistance = 0.005;
    ssaoPass.maxDistance = 0.18;
    composer.addPass(ssaoPass);

    postGradePass = new ShaderPass(PostGradeVignetteShader);
    postGradePass.enabled = false;
    composer.addPass(postGradePass);

    // ─────────────────────────────────────────────────────────────
    // Raycaster — canvas click → select part
    // We track pointer delta to distinguish click from orbit drag.
    // ─────────────────────────────────────────────────────────────
    const raycaster = new THREE.Raycaster();
    const _ndcPt    = new THREE.Vector2();
    let _ptrDown    = null;   // { x, y } at pointerdown
    let _ptrDragged = false;

    renderer.domElement.addEventListener('pointerdown', (e) => {
        _ptrDown    = { x: e.clientX, y: e.clientY };
        _ptrDragged = false;
    });
    renderer.domElement.addEventListener('pointermove', (e) => {
        if (_ptrDown) {
            const dx = e.clientX - _ptrDown.x, dy = e.clientY - _ptrDown.y;
            if (dx * dx + dy * dy > 16) _ptrDragged = true;  // >4px threshold
        }
    });
    renderer.domElement.addEventListener('pointerup', (e) => {
        const wasClick = _ptrDown && !_ptrDragged;
        _ptrDown = null;
        if (!wasClick || !loadedModel) return;

        const rect = renderer.domElement.getBoundingClientRect();
        _ndcPt.set(
            ((e.clientX - rect.left) / rect.width)  *  2 - 1,
            ((e.clientY - rect.top)  / rect.height) * -2 + 1
        );
        raycaster.setFromCamera(_ndcPt, isOrtho ? orthoCamera : camera);

        const pickable = [];
        for (const entry of partMap.values()) {
            if (!entry.visible) continue;
            entry.meshes.forEach(m => { if (!m.userData.isOutline) pickable.push(m); });
        }

        const hits = raycaster.intersectObjects(pickable, false);
        if (!hits.length) {
            // Click on empty space → deselect all
            clearSelection();
            return;
        }

        selectMesh(hits[0].object, { ctrl: e.ctrlKey || e.metaKey, shift: e.shiftKey });
    });

    // iPhone 16 Pro logical resolution: 393 × 852 pt
    const IPHONE_W = 393, IPHONE_H = 852;
    const IPHONE_ASPECT = IPHONE_W / IPHONE_H;   // ≈ 0.4613
    let isIPhonePreview = false;

    function calcIPhoneCanvasSize() {
        const paneW = container.parentElement.clientWidth  || window.innerWidth;
        const paneH = container.parentElement.clientHeight || window.innerHeight;
        // Fit the phone portrait rect inside the pane with comfortable padding
        const pad = 64;
        const maxW = paneW - pad, maxH = paneH - pad;
        let cW, cH;
        if (maxW / IPHONE_ASPECT <= maxH) {
            cW = maxW; cH = maxW / IPHONE_ASPECT;
        } else {
            cH = maxH; cW = maxH * IPHONE_ASPECT;
        }
        return { w: Math.round(cW), h: Math.round(cH) };
    }

    function applyIPhoneCanvasSize() {
        const { w, h } = calcIPhoneCanvasSize();
        container.style.width  = w + 'px';
        container.style.height = h + 'px';
        setRenderSize(w, h);
        camera.aspect = w / h;
        camera.updateProjectionMatrix();
        // Size the frame overlay to match exactly
        const frame = document.getElementById('iphone-frame');
        frame.style.width  = w + 'px';
        frame.style.height = h + 'px';
    }

    function toggleIPhonePreview() {
        isIPhonePreview = !isIPhonePreview;
        const vp = document.getElementById('viewer-pane');
        const btn = document.getElementById('iphone-preview-btn');
        vp.classList.toggle('iphone-preview', isIPhonePreview);
        btn.classList.toggle('iphone-btn-active', isIPhonePreview);
        if (isIPhonePreview) {
            applyIPhoneCanvasSize();
        } else {
            // Restore full-pane canvas
            container.style.width  = '';
            container.style.height = '';
            const { w, h } = { w: container.clientWidth, h: container.clientHeight };
            if (w && h) {
                setRenderSize(w, h);
                camera.aspect = w / h;
                camera.updateProjectionMatrix();
            }
        }
    }

    document.getElementById('iphone-preview-btn').addEventListener('click', toggleIPhonePreview);

    new ResizeObserver(() => {
        if (isIPhonePreview) { applyIPhoneCanvasSize(); return; }
        const w = container.clientWidth, h = container.clientHeight;
        if (!w || !h) return;
        setRenderSize(w, h);
        camera.aspect = w / h;
        camera.updateProjectionMatrix();
    }).observe(container);

    renderer.setAnimationLoop(() => {
        controls.update();
        if (isOrtho) {
            const d = Math.max(0.001, camera.position.distanceTo(controls.target));
            const halfH = d * Math.tan(THREE.MathUtils.degToRad(camera.fov * 0.5));
            const w = container.clientWidth, h = container.clientHeight;
            const asp = (w > 0 && h > 0) ? w / h : 1;
            orthoCamera.left   = -halfH * asp;
            orthoCamera.right  =  halfH * asp;
            orthoCamera.top    =  halfH;
            orthoCamera.bottom = -halfH;
            orthoCamera.near   = camera.near;
            orthoCamera.far    = camera.far;
            orthoCamera.position.copy(camera.position);
            orthoCamera.quaternion.copy(camera.quaternion);
            orthoCamera.updateProjectionMatrix();
        }
        const activeCamera = isOrtho ? orthoCamera : camera;
        if (renderPass) renderPass.camera = activeCamera;
        if (ssaoPass) ssaoPass.camera = activeCamera;
        updateCameraHUD();
        composer.render();
    });

    // ── Lights (photorealistic — matches viewer.html setup) ─────────────────────
    const keyLight = new THREE.DirectionalLight(0xfff8f0, 2.0);
    keyLight.position.set(1.5, 2.5, 2.0);
    keyLight.castShadow = true;
    keyLight.shadow.mapSize.setScalar(1024);
    keyLight.shadow.camera.near   = 0.1;
    keyLight.shadow.camera.far    = 10;
    keyLight.shadow.camera.left   = -2;
    keyLight.shadow.camera.right  =  2;
    keyLight.shadow.camera.top    =  2;
    keyLight.shadow.camera.bottom = -2;
    keyLight.shadow.radius = 8;
    keyLight.shadow.bias   = -0.0005;
    scene.add(keyLight);
    const fillLight = new THREE.DirectionalLight(0xb0c8ff, 0.55);
    fillLight.position.set(-2, 1, -1.5);
    scene.add(fillLight);
    const rimLight = new THREE.DirectionalLight(0xdde8ff, 0.45);
    rimLight.position.set(0, -1, -2);
    scene.add(rimLight);
    const ambientLight = new THREE.AmbientLight(0xffffff, 0.1);
    scene.add(ambientLight);

    // ── IBL (procedural RoomEnvironment) ─────────────────────────────────────────
    const _pmrem   = new THREE.PMREMGenerator(renderer);
    const _roomEnv = new RoomEnvironment();
    const _envTex  = _pmrem.fromScene(_roomEnv, 0.04).texture;
    scene.environment          = _envTex;
    scene.environmentIntensity = 1.0;
    _roomEnv.dispose();

    // ── Shadow-catcher floor ──────────────────────────────────────────────────────
    const groundMesh = new THREE.Mesh(
        new THREE.CircleGeometry(1.8, 64),
        new THREE.ShadowMaterial({ opacity: 0.38, transparent: true })
    );
    groundMesh.rotation.x = -Math.PI / 2;
    groundMesh.position.y = -0.52;
    groundMesh.receiveShadow = true;
    scene.add(groundMesh);

    // ─────────────────────────────────────────────────────────────
    // Camera HUD — live readout, FOV control, camera code export
    // ─────────────────────────────────────────────────────────────
    function setHudXYZ(idX, idY, idZ, vec) {
        if (!cameraModule) return;
        cameraModule.setHudXYZ(idX, idY, idZ, vec);
    }

    function setHudXYZDeg(idX, idY, idZ, euler) {
        if (!cameraModule) return;
        cameraModule.setHudXYZDeg(idX, idY, idZ, euler);
    }

    function updateCameraHUD() {
        if (!cameraModule) return;
        cameraModule.updateCameraHUD();
    }

    function syncOrbitTarget() {
        if (!cameraModule) return;
        cameraModule.syncOrbitTarget();
    }

    function fitCameraToModel() {
        if (!cameraModule) return;
        cameraModule.fitCameraToModel();
    }

    function generateCameraCode() {
        const p  = camera.position;
        const t  = controls.target;
        const fv = Math.round(camera.fov * 10) / 10;
        const f  = n => n.toFixed(4);
        const lines = [
            `// ── Camera (paste into viewer.html after scene/controls setup) ──`,
            `USE_ORTHO = ${isOrtho};`,
            `camera.fov = ${fv};`,
            `camera.updateProjectionMatrix();`,
            `camera.position.set(${f(p.x)}, ${f(p.y)}, ${f(p.z)});`,
            `controls.target.set(${f(t.x)}, ${f(t.y)}, ${f(t.z)});`,
            `controls.update();`,
            `if (USE_ORTHO) syncOrthoCamera();`,
        ];
        if (loadedModel) {
            const rx = Math.round(THREE.MathUtils.radToDeg(loadedModel.rotation.x) * 10) / 10;
            const ry = Math.round(THREE.MathUtils.radToDeg(loadedModel.rotation.y) * 10) / 10;
            const rz = Math.round(THREE.MathUtils.radToDeg(loadedModel.rotation.z) * 10) / 10;
            const d  = n => (n * Math.PI / 180).toFixed(6);
            lines.push(`// ── Model rotation ──`);
            lines.push(`rootModel.rotation.set(${d(rx)}, ${d(ry)}, ${d(rz)}); // ${rx}° ${ry}° ${rz}°`);
        }
        return lines.join('\n');
    }

    function applyModelRotationDeg(x, y, z, persist = true) {
        if (!cameraModule) return;
        cameraModule.applyModelRotationDeg(x, y, z, persist);
    }

    function toggleOrtho() {
        if (!cameraModule) return;
        cameraModule.toggleOrtho();
    }

    // ─────────────────────────────────────────────────────────────
    // Material management (extracted to material-mapper-materials.js)
    // The materialsModule handles all material properties, schema,
    // Three.js objects, and UI building for the materials panel.
    // ─────────────────────────────────────────────────────────────

    // ─────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────
    let partMap         = new Map();   // displayName → { mesh, origMat, origName, assignedKey, visible }
    let loadedModel     = null;
    let loadedFileName  = 'model';
    let cameraModule    = null;
    let sceneModule     = null;
    let sceneState      = null;
    let materialsModule = null;
    let persistenceModule = null;
    let loaderModule    = null;
    let shellModule     = null;
    let toolsModule     = null;

    function fallbackGuessKey(name) {
        const normalizedName = String(name || '').toLowerCase();
        if (/led|rgb|emitter|die/.test(normalizedName)) return 'ledMat';
        if (/diffuser|lens|cap|dome/.test(normalizedName)) return 'ledCapMat';
        if (/button|btn|trigger/.test(normalizedName)) return 'buttonMat';
        if (/pcb|board|substrate|fr4/.test(normalizedName)) return 'pcbMat';
        if (/clip|spring|pin|contact|metal|brass|steel|screw|nut/.test(normalizedName)) return 'metalMat';
        if (/rubber|gasket|seal|grip/.test(normalizedName)) return 'rubberMat';
        return 'housingMat';
    }

    // Module functions — declared here, assigned after modules init
    let matProps, MAT_OBJ, MAT_SCHEMA;
    let setProp = () => {}, selectMesh = () => false, clearSelection = () => {}, selectAllVisible = () => {}, syncSelectionEditor = () => {}, setVisibility = () => {}, syncShowAllBtn = () => {}, buildEditor = () => {}, buildPartsUI = () => {}, applyMaterials = () => {}, generateMaterialsJs = () => '', guessKey = fallbackGuessKey, updateCode = () => {};
    let loadBuffer = () => {};
    let importFromCode = () => ({ matCount: 0, ruleCount: 0 });
    let saveLastFileToDB = () => {}, loadLastFileFromDB = () => {}, persistSaveState = () => {}, restoreState = () => false;

    function saveState() {
        persistSaveState?.();
    }

    // ─────────────────────────────────────────────────────────────
    // Visibility toggle
    // ─────────────────────────────────────────────────────────────
    const EYE_OPEN_SVG = `<svg width="14" height="10" viewBox="0 0 14 10" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M1 5C2.6 2 4.6 1 7 1C9.4 1 11.4 2 13 5C11.4 8 9.4 9 7 9C4.6 9 2.6 8 1 5Z" stroke="currentColor" stroke-width="1.3"/><circle cx="7" cy="5" r="1.8" fill="currentColor"/></svg>`;
    const EYE_SHUT_SVG = `<svg width="14" height="10" viewBox="0 0 14 10" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M1 5C2.6 2 4.6 1 7 1C9.4 1 11.4 2 13 5" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/><line x1="2" y1="9" x2="12" y2="1" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/></svg>`;

    document.getElementById('show-all-btn').addEventListener('click', () => {
        for (const [name] of partMap) setVisibility(name, true);
    });

    // Cmd/Ctrl + A → select all visible parts
    document.addEventListener('keydown', (e) => {
        if (!(e.metaKey || e.ctrlKey) || e.key !== 'a') return;
        if (!partMap.size) return;
        // Don't intercept if focus is inside a text input
        const tag = document.activeElement?.tagName;
        if (tag === 'INPUT' || tag === 'TEXTAREA') return;
        e.preventDefault();
        selectAllVisible();
    });

    // ─────────────────────────────────────────────────────────────
    // buildPartsUI removed - delegated to materialsModule

    function updatePartCount() {
        const total   = partMap.size;
        const visible = [...document.querySelectorAll('.part-row:not(.hidden)')].length;
        document.getElementById('part-count').textContent =
            visible < total ? `${visible} / ${total}` : `${total} part${total !== 1 ? 's' : ''}`;
    }

    // ─────────────────────────────────────────────────────────────
    // Search / filter
    // ─────────────────────────────────────────────────────────────
    document.getElementById('search-input').addEventListener('input', (e) => {
        const q = e.target.value.trim().toLowerCase();
        document.querySelectorAll('.part-row').forEach(row => {
            const match = !q || row.dataset.name.toLowerCase().includes(q);
            row.classList.toggle('hidden', !match);
        });
        updatePartCount();
    });

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
    // Reset button
    // ─────────────────────────────────────────────────────────────
    document.getElementById('reset-btn').addEventListener('click', () => {
        for (const entry of partMap.values()) {
            entry.assignedKey = guessKey(entry.origName ?? '');
            entry.visible = true;
            entry.meshes.forEach(m => { m.visible = true; });
        }
        clearSelection();
        applyMaterials();
        buildPartsUI();
        syncShowAllBtn();
        saveState();
    });

    // ─────────────────────────────────────────────────────────────
    // Toast
    // ─────────────────────────────────────────────────────────────
    let toastTimer;
    function showToast(msg) {
        const t = document.getElementById('toast');
        t.textContent = msg;
        t.classList.add('show');
        clearTimeout(toastTimer);
        toastTimer = setTimeout(() => t.classList.remove('show'), 2000);
    }

    // ─────────────────────────────────────────────────────────────
    // Export GLB (visible parts only)
    // ─────────────────────────────────────────────────────────────
    document.getElementById('export-btn').addEventListener('click', () => toolsModule?.exportGLB());

    // ─────────────────────────────────────────────────────────────
    // Auto Z-Fighting Fix
    // Detects coplanar overlapping mesh pairs by checking whether
    // their world-space AABB intersection is "flat" (thinnest dim
    // < 1 % of largest). For each pair, ensures the smaller-volume
    // mesh's material (the surface "on top") has a polygonOffset
    // factor at least 1 step more negative than the larger mesh's
    // material. Re-runs correctly even when offset is already set.
    // ─────────────────────────────────────────────────────────────
    document.getElementById('zfix-btn').addEventListener('click', () => toolsModule?.autoFixZFighting());

    cameraModule = window.MaterialMapperCameraModule({
        THREE,
        camera,
        orthoCamera,
        controls,
        groundMesh,
        saveState,
        showToast,
        generateCameraCode,
        getLoadedModel: () => loadedModel,
        getIsOrtho: () => isOrtho,
        setIsOrtho: (value) => { isOrtho = !!value; },
    });
    cameraModule.init();

    // Scene settings panel moved to material-mapper-scene.js
    sceneModule = window.MaterialMapperSceneModule({
        THREE,
        renderer,
        scene,
        keyLight,
        fillLight,
        rimLight,
        ambientLight,
        groundMesh,
        envTexture: _envTex,
        bloomPass,
        ssaoPass,
        postGradePass,
        saveState,
    });
    sceneState = sceneModule.getState();
    try {
        sceneModule.init();
    } catch (error) {
        console.warn('[Material Mapper] Scene module init failed; continuing without full scene controls.', error);
    }

    // Materials management
    materialsModule = window.MaterialMapperMaterialsModule({
        THREE,
        partMap,
        loadedModel: () => loadedModel,
        saveState: () => saveState(),
        showToast,
        updatePartCount: () => updatePartCount(),
        generateCameraCode: () => generateCameraCode(),
    });

    // Persistence (state save/load + IDB caching)
    persistenceModule = window.MaterialMapperPersistenceModule({
        loadBuffer: (...args) => loadBuffer(...args),
        partMap,
        matProps: () => materialsModule.getMatProps(),
        MAT_OBJ: () => materialsModule.getMAT_OBJ(),
        loadedFileName: () => loadedFileName,
        loadedModel: () => loadedModel,
        isOrtho: () => isOrtho,
        hudState: () => cameraModule?.getHudState?.() ?? null,
        shellState: () => shellModule?.getLayoutState?.() ?? null,
        camera,
        controls,
        sceneState: () => sceneState,
        THREE,
        showToast,
        importFromCode: (text) => importFromCode(text),
    });

    loaderModule = window.MaterialMapperLoaderModule({
        THREE,
        GLTFLoader,
        scene,
        camera,
        groundMesh,
        partMap,
        getLoadedModel: () => loadedModel,
        setLoadedModel: (value) => { loadedModel = value; },
        setLoadedFileName: (value) => { loadedFileName = value; },
        resetSelection: () => clearSelection(),
        guessKey: (name) => guessKey(name),
        fitCameraToModel,
        applyMaterials: () => applyMaterials(),
        buildPartsUI: () => buildPartsUI(),
        syncShowAllBtn: () => syncShowAllBtn(),
        buildEditor: (...args) => buildEditor(...args),
        syncEditor: () => syncSelectionEditor(),
        updateCode: () => updateCode(),
        getMatProps: () => matProps,
        getMAT_OBJ: () => MAT_OBJ,
        saveLastFileToDB: (...args) => saveLastFileToDB(...args),
        restoreState: (...args) => restoreState(...args),
        getRestoreCallbacks: () => ({
            applyMaterials,
            buildPartsUI,
            buildEditor,
            syncShowAllBtn,
            setIsOrtho: (nextIsOrtho) => {
                if (typeof nextIsOrtho !== 'boolean' || nextIsOrtho === isOrtho) return;
                cameraModule?.toggleOrtho?.();
            },
            setHudXYZ: cameraModule?.setHudXYZ,
            applyModelRotationDeg: cameraModule?.applyModelRotationDeg,
            restoreHudState: cameraModule?.restoreHudState,
            syncOrbitTarget: cameraModule?.syncOrbitTarget,
            restoreLayoutState: shellModule?.restoreLayoutState,
            mergeSceneState: sceneModule?.mergeState,
            applySceneState: sceneModule?.applyAll,
            syncScenePanel: sceneModule?.syncScenePanel,
        }),
        onModelLoaded: (fileName) => shellModule?.onModelLoaded(fileName),
        saveState,
        showToast,
    });

    // Extract and bind module methods
    matProps = materialsModule.getMatProps();
    MAT_OBJ = materialsModule.getMAT_OBJ();
    MAT_SCHEMA = materialsModule.getMAT_SCHEMA();
    ({ setProp, selectMesh, clearSelection, selectAllVisible, syncSelectionEditor, setVisibility, syncShowAllBtn, buildEditor, buildPartsUI, applyMaterials, generateMaterialsJs, guessKey, updateCode } = materialsModule);
    ({ loadBuffer, importFromCode } = loaderModule);
    ({ saveLastFileToDB, loadLastFileFromDB, saveState: persistSaveState, restoreState } = persistenceModule);

    toolsModule = window.MaterialMapperToolsModule({
        THREE,
        GLTFExporter,
        getLoadedModel: () => loadedModel,
        getLoadedFileName: () => loadedFileName,
        partMap,
        getMatProps: () => matProps,
        setProp,
        syncEditor: () => syncSelectionEditor(),
        showToast,
    });

    shellModule = window.MaterialMapperShellModule({
        loadBuffer: (...args) => loadBuffer(...args),
        importFromCode: (...args) => importFromCode(...args),
        getPartMap: () => partMap,
        getSceneModule: () => sceneModule,
        saveState,
        showToast,
    });
    shellModule.init();

    // Auto-reload last opened file on page open
    loadLastFileFromDB();
};  // end MaterialMapperApp
