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
            selectedParts.clear();
            primarySelected = null;
            document.querySelectorAll('.part-row').forEach(r => r.classList.remove('selected'));
            clearOutlines();
            buildEditor(null);
            return;
        }

        const hit = hits[0].object;
        for (const [displayName, entry] of partMap) {
            if (entry.meshes.includes(hit)) {
                selectPart(displayName, { ctrl: e.ctrlKey || e.metaKey, shift: e.shiftKey });
                break;
            }
        }
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
    let selectedParts   = new Set();   // set of selected displayNames
    let primarySelected = null;        // the anchor/primary for editor + shift-range
    let cameraModule    = null;
    let sceneModule     = null;
    let sceneState      = null;
    let materialsModule = null;
    let persistenceModule = null;

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
    let setProp = () => {}, selectPart = () => {}, setVisibility = () => {}, syncShowAllBtn = () => {}, buildEditor = () => {}, buildPartsUI = () => {}, applyMaterials = () => {}, guessKey = fallbackGuessKey, updateCode = () => {};
    let saveLastFileToDB = () => {}, loadLastFileFromDB = () => {}, persistSaveState = () => {}, restoreState = () => false;

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

    // Material selection and UI management functions are delegated to materialsModule
    // (selectPart, applyMaterials, setProp, buildEditor, buildPartsUI, etc.)

    // ─────────────────────────────────────────────────────────────
    // guessKey removed - delegated to materialsModule

    // ─────────────────────────────────────────────────────────────
    // applyMaterials removed - delegated to materialsModule

    // ─────────────────────────────────────────────────────────────
    // setProp removed - delegated to materialsModule

    // ─────────────────────────────────────────────────────────────
    // buildEditor removed - delegated to materialsModule

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

    // ─────────────────────────────────────────────────────────────
    // Generate code output
    // Outputs updated material definitions + MATERIAL_RULES
    // ─────────────────────────────────────────────────────────────
    

    

    // Three.js MeshPhysicalMaterial defaults — skip these in generated code
    const PROP_DEFAULTS = {
        emissive: '#000000', emissiveIntensity: 0, transmission: 0,
        thickness: 0, ior: 1.5, opacity: 1, transparent: false,
        toneMapped: true, side: 'Front', metalness: 0,
        polygonOffset: false, polygonOffsetFactor: 0, polygonOffsetUnits: 0,
    };

    

    

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
        clearOutlines();
        selectedParts.clear();
        primarySelected = null;
        applyMaterials();
        buildPartsUI();
        syncShowAllBtn();
        buildEditor(null);
        saveState();
    });

    // ─────────────────────────────────────────────────────────────
    // GLTF loading
    // ─────────────────────────────────────────────────────────────
    const loader = new GLTFLoader();

    function loadBuffer(buffer, fileName) {
        loader.parse(buffer, '', (gltf) => {
            clearOutlines();
            if (loadedModel) scene.remove(loadedModel);
            partMap.clear();
            selectedParts.clear();
            primarySelected = null;

            const model = gltf.scene;

            // ── Group face-group meshes into logical parts ───────────────────
            // Onshape glTF exports come in two layouts:
            //   A) Part = parent Group → N child Meshes (one per face group)
            //   B) Flat: N Mesh siblings all sharing the same name (same part)
            // We group by parent UUID (layout A) or by parentUUID+name (layout B).
            const groupMap = new Map();   // key → { rawName, meshes, origMats }

            model.traverse((child) => {
                if (!child.isMesh) return;
                const parent      = child.parent;
                const sceneRoot   = parent === model || parent === gltf.scene || !parent;

                const ownName  = child.name?.trim() || '';
                const parentName = (!sceneRoot && parent.name?.trim()) || '';

                let groupKey, rawName;
                if (!sceneRoot && parentName) {
                    // Layout A: named parent group → use parent UUID
                    groupKey = parent.uuid;
                    rawName  = parentName;
                } else {
                    // Layout B (flat) or unknown: group siblings with identical names
                    groupKey = (sceneRoot ? (parent?.uuid ?? 'root') : parent.uuid) + '|' + (ownName || child.uuid);
                    rawName  = ownName;
                }

                if (!groupMap.has(groupKey)) {
                    groupMap.set(groupKey, { rawName, meshes: [], origMats: [] });
                }
                const g = groupMap.get(groupKey);
                g.meshes.push(child);
                g.origMats.push(child.material);
            });

            // ── Deduplicate display names ────────────────────────────────────
            const nameCounts = {};
            for (const { rawName, meshes, origMats } of groupMap.values()) {
                let displayName = rawName || '(unnamed)';
                if (nameCounts[displayName] === undefined) {
                    nameCounts[displayName] = 0;
                } else {
                    nameCounts[displayName]++;
                    displayName = `${displayName} (${nameCounts[displayName]})`;
                }

                partMap.set(displayName, {
                    meshes,
                    origMats,
                    origName:    rawName,
                    assignedKey: guessKey(rawName),
                    visible:     true,
                });
            }

            // Fit model to unit cube
            const box    = new THREE.Box3().setFromObject(model);
            const size   = box.getSize(new THREE.Vector3());
            const centre = box.getCenter(new THREE.Vector3());
            const maxDim = Math.max(size.x, size.y, size.z) || 1;
            const scale  = 1.0 / maxDim;
            model.scale.setScalar(scale);
            model.position.sub(centre.multiplyScalar(scale));

            scene.add(model);
            loadedModel = model;

            fitCameraToModel();
            const hudFovEl = document.getElementById('hud-fov');
            if (hudFovEl) hudFovEl.value = Math.round(camera.fov);

            // Enable shadows on all loaded meshes + snap ground to model bottom
            model.traverse(c => {
                if (c.isMesh && !c.userData.isOutline) {
                    c.castShadow    = true;
                    c.receiveShadow = true;
                }
            });
            const _mbox = new THREE.Box3().setFromObject(model);
            groundMesh.position.y = _mbox.min.y - 0.008;

            document.getElementById('drop-overlay').classList.add('hidden');
            document.getElementById('search-input').value = '';
            document.getElementById('export-btn').style.display = '';
            document.getElementById('zfix-btn').style.display   = '';
            document.title = `Material Mapper — ${fileName}`;
            loadedFileName = fileName;
            saveLastFileToDB(fileName, buffer);

            const didRestore = restoreState(fileName, {
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
                syncOrbitTarget: cameraModule?.syncOrbitTarget,
                mergeSceneState: sceneModule?.mergeState,
                applySceneState: sceneModule?.applyAll,
                syncScenePanel: sceneModule?.syncScenePanel,
            });
            if (!didRestore) {
                applyMaterials();
                buildPartsUI();
                syncShowAllBtn();
                buildEditor(null);
            }
            if (didRestore) showToast('Session restored');

        }, (err) => {
            console.error('[Material Mapper] GLTF parse error:', err);
            alert('Could not load model:\n' + (err?.message ?? String(err)));
        });
    }

    // ─────────────────────────────────────────────────────────────
    // File input + drag-drop
    // ─────────────────────────────────────────────────────────────
    document.getElementById('file-input').addEventListener('change', (e) => {
        const file = e.target.files[0];
        if (!file) return;
        file.arrayBuffer().then(buf => loadBuffer(buf, file.name));
        e.target.value = '';
    });

    const viewerPane  = document.getElementById('viewer-pane');
    const dropOverlay = document.getElementById('drop-overlay');

    viewerPane.addEventListener('dragover',  (e) => { e.preventDefault(); dropOverlay.classList.add('drag-active'); });
    viewerPane.addEventListener('dragleave', ()  => dropOverlay.classList.remove('drag-active'));
    viewerPane.addEventListener('drop', (e) => {
        e.preventDefault();
        dropOverlay.classList.remove('drag-active');
        const file = e.dataTransfer.files[0];
        if (file) file.arrayBuffer().then(buf => loadBuffer(buf, file.name));
    });
    dropOverlay.addEventListener('click', () => document.getElementById('file-input').click());

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
    // Code modal
    // ─────────────────────────────────────────────────────────────
    const codeModal      = document.getElementById('code-modal');
    const showCodeBtn    = document.getElementById('show-code-btn');
    const codeModalClose = document.getElementById('code-modal-close');

    showCodeBtn.addEventListener('click', () => codeModal.classList.remove('hidden'));
    codeModalClose.addEventListener('click', () => codeModal.classList.add('hidden'));
    codeModal.addEventListener('click', (e) => {
        if (e.target === codeModal) codeModal.classList.add('hidden');
    });
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') codeModal.classList.add('hidden');
    });

    // ─────────────────────────────────────────────────────────────
    // Layout toggle (stacked ↔ side-by-side)
    // ─────────────────────────────────────────────────────────────
    const panelBody  = document.getElementById('panel-body');
    const layoutBtn  = document.getElementById('layout-btn');
    const editorSide = document.getElementById('editor-side');

    layoutBtn.addEventListener('click', () => {
        const isSide = panelBody.classList.toggle('side-by-side');
        layoutBtn.title = isSide ? 'Switch to stacked layout' : 'Switch to side-by-side layout';
        layoutBtn.textContent = isSide ? '⊟' : '⊞';
        // Reset any inline sizes set by drag so flex takes over
        editorSide.style.height = '';
        editorSide.style.width  = '';
        editorSide.style.flex   = '';
    });

    // ─────────────────────────────────────────────────────────────
    // Panel (viewer ↔ panel) resize handle drag
    // ─────────────────────────────────────────────────────────────
    const panelEl           = document.getElementById('panel');
    const panelResizeHandle = document.getElementById('panel-resize-handle');

    panelResizeHandle.addEventListener('pointerdown', (e) => {
        e.preventDefault();
        panelResizeHandle.classList.add('dragging');
        panelResizeHandle.setPointerCapture(e.pointerId);

        const startX    = e.clientX;
        const startW    = panelEl.offsetWidth;
        const layoutW   = panelEl.parentElement.offsetWidth;
        const MIN = 200, MAX = layoutW * 0.70;

        function onMove(ev) {
            const newW = Math.max(MIN, Math.min(MAX, startW - (ev.clientX - startX)));
            panelEl.style.width = newW + 'px';
        }
        function onUp() {
            panelResizeHandle.classList.remove('dragging');
            panelResizeHandle.removeEventListener('pointermove', onMove);
            panelResizeHandle.removeEventListener('pointerup', onUp);
        }
        panelResizeHandle.addEventListener('pointermove', onMove);
        panelResizeHandle.addEventListener('pointerup', onUp);
    });

    // ─────────────────────────────────────────────────────────────
    // Resize handle drag (parts ↔ editor within panel)
    // ─────────────────────────────────────────────────────────────
    const resizeHandle = document.getElementById('resize-handle');

    resizeHandle.addEventListener('pointerdown', (e) => {
        e.preventDefault();
        resizeHandle.classList.add('dragging');
        resizeHandle.setPointerCapture(e.pointerId);

        const isSide     = panelBody.classList.contains('side-by-side');
        const startPos   = isSide ? e.clientX : e.clientY;
        const startSize  = isSide ? editorSide.offsetWidth : editorSide.offsetHeight;
        const panelSize  = isSide ? panelBody.offsetWidth : panelBody.offsetHeight;
        const MIN = 80, MAX_FRAC = 0.85;

        function onMove(ev) {
            const delta = isSide ? (startPos - ev.clientX) : (startPos - ev.clientY);
            const newSize = Math.max(MIN, Math.min(panelSize * MAX_FRAC, startSize + delta));
            if (isSide) {
                editorSide.style.flex  = 'none';
                editorSide.style.width = newSize + 'px';
            } else {
                editorSide.style.height = newSize + 'px';
            }
        }

        function onUp() {
            resizeHandle.classList.remove('dragging');
            resizeHandle.removeEventListener('pointermove', onMove);
            resizeHandle.removeEventListener('pointerup', onUp);
        }

        resizeHandle.addEventListener('pointermove', onMove);
        resizeHandle.addEventListener('pointerup', onUp);
    });

    // ─────────────────────────────────────────────────────────────
    // Export GLB (visible parts only)
    // ─────────────────────────────────────────────────────────────
    document.getElementById('export-btn').addEventListener('click', () => {
        if (!loadedModel) return;
        // Temporarily hide outline meshes so they're not baked in
        const outlines = [];
        loadedModel.traverse(c => {
            if (c.userData.isOutline) { outlines.push(c); c.visible = false; }
        });
        const exporter = new GLTFExporter();
        exporter.parse(loadedModel, (glb) => {
            outlines.forEach(c => { c.visible = true; });
            const base = loadedFileName.replace(/\.[^.]+$/, '');
            const blob = new Blob([glb], { type: 'model/gltf-binary' });
            const url  = URL.createObjectURL(blob);
            const a    = document.createElement('a');
            a.href = url; a.download = base + '_visible.glb'; a.click();
            URL.revokeObjectURL(url);
            showToast('GLB exported!');
        }, (err) => {
            outlines.forEach(c => { c.visible = true; });
            console.error('[Export GLB]', err);
            showToast('Export failed — see console');
        }, { binary: true, onlyVisible: true });
    });

    // ─────────────────────────────────────────────────────────────
    // Auto Z-Fighting Fix
    // Detects coplanar overlapping mesh pairs by checking whether
    // their world-space AABB intersection is "flat" (thinnest dim
    // < 1 % of largest). For each pair, ensures the smaller-volume
    // mesh's material (the surface "on top") has a polygonOffset
    // factor at least 1 step more negative than the larger mesh's
    // material. Re-runs correctly even when offset is already set.
    // ─────────────────────────────────────────────────────────────
    document.getElementById('zfix-btn').addEventListener('click', autoFixZFighting);

    function autoFixZFighting() {
        if (!loadedModel) return;

        loadedModel.updateMatrixWorld(true);

        // Collect all non-outline meshes with world-space AABBs
        const items = [];
        loadedModel.traverse(c => {
            if (!c.isMesh || c.userData.isOutline || !c.geometry) return;
            c.geometry.computeBoundingBox();
            const box = c.geometry.boundingBox.clone().applyMatrix4(c.matrixWorld);
            items.push({ mesh: c, box });
        });

        // Reverse map: mesh UUID → partMap displayName
        const meshToPartName = new Map();
        for (const [name, entry] of partMap) {
            for (const m of entry.meshes) meshToPartName.set(m.uuid, name);
        }

        // Collect unique coplanar pairs as { winnerKey, loserKey }
        const pairs = [];
        const seenPairs = new Set();
        let sameMaterialPairs = 0;
        let keepPairs = 0;

        console.group('[Z-Fix] Detection pass');
        console.log(`Meshes scanned: ${items.length}`);

        for (let i = 0; i < items.length; i++) {
            for (let j = i + 1; j < items.length; j++) {
                const a = items[i], b = items[j];
                if (!a.box.intersectsBox(b.box)) continue;

                // Intersection size
                const ix = Math.min(a.box.max.x, b.box.max.x) - Math.max(a.box.min.x, b.box.min.x);
                const iy = Math.min(a.box.max.y, b.box.max.y) - Math.max(a.box.min.y, b.box.min.y);
                const iz = Math.min(a.box.max.z, b.box.max.z) - Math.max(a.box.min.z, b.box.min.z);
                const dims = [ix, iy, iz].sort((x, y) => x - y); // ascending

                // Coplanar: thinnest dimension is < 1 % of largest
                if (dims[2] < 1e-9 || dims[0] / dims[2] > 0.01) continue;

                // Smaller volume mesh sits on top (winner)
                const sizeA = a.box.getSize(new THREE.Vector3());
                const sizeB = b.box.getSize(new THREE.Vector3());
                const volA  = sizeA.x * sizeA.y * sizeA.z;
                const volB  = sizeB.x * sizeB.y * sizeB.z;
                const [winner, loser] = volA <= volB ? [a, b] : [b, a];

                const winName = meshToPartName.get(winner.mesh.uuid);
                const losName = meshToPartName.get(loser.mesh.uuid);

                const winKey = winName ? partMap.get(winName)?.assignedKey : null;
                const losKey = losName ? partMap.get(losName)?.assignedKey : null;

                // Log every detected coplanar pair regardless of material state
                console.log(`Coplanar pair — dims:[${dims.map(d=>d.toFixed(5)).join(', ')}] ratio:${(dims[0]/dims[2]).toFixed(4)}`, {
                    winner: winName ?? '(unmapped)', winnerMat: winKey ?? '?', volWinner: volA <= volB ? volA : volB,
                    loser:  losName ?? '(unmapped)', loserMat:  losKey ?? '?', volLoser:  volA <= volB ? volB : volA,
                });

                if (!winName || !losName) continue;
                if (!winKey || !losKey) continue;

                if (winKey === '_keep' || losKey === '_keep') {
                    keepPairs++;
                    continue;
                }
                if (!(winKey in matProps) || !(losKey in matProps)) continue;

                if (winKey === losKey) {
                    sameMaterialPairs++;
                    console.warn(`  → same material (${winKey}) on both sides — can't fix with polygon offset`);
                    continue;
                }

                const pairId = [winKey, losKey].sort().join('||');
                if (seenPairs.has(pairId)) continue;
                seenPairs.add(pairId);
                pairs.push({ winnerKey: winKey, loserKey: losKey });
            }
        }
        console.groupEnd();

        // For each pair, ensure winner's factor is more negative than loser's.
        // If already correct, leave untouched. Always enables polygonOffset on winner.
        let count = 0;
        // Reset all factors to 0 first so repeated runs don't cascade to
        // increasingly negative values (-68, -82, etc.)
        for (const key of Object.keys(matProps)) {
            if (matProps[key].polygonOffsetFactor !== 0) setProp(key, 'polygonOffsetFactor', 0);
            if (matProps[key].polygonOffsetUnits  !== 0) setProp(key, 'polygonOffsetUnits',  0);
            if (matProps[key].polygonOffset)             setProp(key, 'polygonOffset', false);
        }

        // Snapshot factors NOW (all 0 after reset) so mid-loop setProp calls
        // can't cascade into later pairs within the same run.
        const factorSnapshot = {};
        for (const key of Object.keys(matProps)) factorSnapshot[key] = 0;

        console.group('[Z-Fix] Apply pass');
        for (const { winnerKey, loserKey } of pairs) {
            const loserFactor  = factorSnapshot[loserKey];
            const neededFactor = loserFactor - 2;

            console.log(`${winnerKey}(snap:${factorSnapshot[winnerKey]}) vs ${loserKey}(snap:${loserFactor}) → setting winner to ${neededFactor}`);

            setProp(winnerKey, 'polygonOffset',       true);
            setProp(winnerKey, 'polygonOffsetFactor',  neededFactor);
            setProp(winnerKey, 'polygonOffsetUnits',   neededFactor);
            count++;
        }
        console.groupEnd();

        // Refresh editor panel if a material is open
        const pEntry = primarySelected ? partMap.get(primarySelected) : null;
        if (pEntry?.assignedKey) buildEditor(pEntry.assignedKey, selectedParts.size);

        const notes = [
            sameMaterialPairs > 0 ? `${sameMaterialPairs} same-material pair${sameMaterialPairs !== 1 ? 's' : ''} can't be auto-fixed (assign separate materials)` : '',
            keepPairs > 0         ? `${keepPairs} pair${keepPairs !== 1 ? 's' : ''} use _keep material (reassign to fix)` : '',
        ].filter(Boolean).join('; ');

        const noPairs = pairs.length === 0 && sameMaterialPairs === 0 && keepPairs === 0;
        showToast(
            noPairs  ? 'No coplanar overlap detected — check console for details' :
            count > 0 ? `Z-fix: updated ${count} material${count !== 1 ? 's' : ''}${notes ? ` · ${notes}` : ''}` :
                        `Offsets already correct${notes ? ` · ${notes}` : ''}`
        );
    }

    // ─────────────────────────────────────────────────────────────
    // State persistence (localStorage)
    // Keyed by filename so each model has its own saved state.
    // ─────────────────────────────────────────────────────────────
    const STORAGE_KEY = 'material-mapper-v1';

    // ── Last-file cache (IndexedDB, no size cap) ────────────────────────
    const IDB_NAME  = 'material-mapper-files';
    const IDB_STORE = 'files';

    

    

    

    function saveState() {
        if (!loadedFileName || partMap.size === 0) return;
        const assignments = {};
        const visibility  = {};
        for (const [name, entry] of partMap) {
            assignments[name] = entry.assignedKey;
            if (!entry.visible) visibility[name] = false;
        }
        const state = {
            matProps:    JSON.parse(JSON.stringify(matProps)),
            assignments,
            visibility,
            camera: {
                position: { x: camera.position.x, y: camera.position.y, z: camera.position.z },
                target:   { x: controls.target.x,  y: controls.target.y,  z: controls.target.z  },
                fov:      camera.fov,
                isOrtho,
            },
            modelRotation: loadedModel ? {
                x: THREE.MathUtils.radToDeg(loadedModel.rotation.x),
                y: THREE.MathUtils.radToDeg(loadedModel.rotation.y),
                z: THREE.MathUtils.radToDeg(loadedModel.rotation.z),
            } : null,
            modelPosition: loadedModel ? {
                x: loadedModel.position.x,
                y: loadedModel.position.y,
                z: loadedModel.position.z,
            } : null,
            sceneState:    JSON.parse(JSON.stringify(sceneState)),
        };
        try {
            const all = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}');
            all[loadedFileName] = state;
            localStorage.setItem(STORAGE_KEY, JSON.stringify(all));
        } catch (e) { console.warn('[State] save failed', e); }
    }

    // ─────────────────────────────────────────────────────────────
    // Import from code — parse generated code and restore state
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
        const { matCount, ruleCount } = importFromCode(text);
        importModal.classList.add('hidden');
        showToast(`Imported: ${matCount} material${matCount !== 1 ? 's' : ''}, ${ruleCount} rule${ruleCount !== 1 ? 's' : ''}`);
    });

    

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
        selectedParts,
        primarySelected: () => primarySelected,
        setPrimarySelected: (value) => { primarySelected = value; },
        saveState: () => saveState(),
        showToast,
        updatePartCount: () => updatePartCount(),
        generateCameraCode: () => generateCameraCode(),
    });

    // Persistence (state save/load + IDB caching)
    persistenceModule = window.MaterialMapperPersistenceModule({
        loadBuffer,
        partMap,
        matProps: () => materialsModule.getMatProps(),
        MAT_OBJ: () => materialsModule.getMAT_OBJ(),
        loadedFileName: () => loadedFileName,
        loadedModel: () => loadedModel,
        camera,
        controls,
        sceneState: () => sceneState,
        THREE,
        showToast,
        importFromCode: (text) => importFromCode(text),
    });

    // Extract and bind module methods
    matProps = materialsModule.getMatProps();
    MAT_OBJ = materialsModule.getMAT_OBJ();
    MAT_SCHEMA = materialsModule.getMAT_SCHEMA();
    ({ setProp, selectPart, setVisibility, syncShowAllBtn, buildEditor, buildPartsUI, applyMaterials, guessKey, updateCode } = materialsModule);
    ({ saveLastFileToDB, loadLastFileFromDB, saveState: persistSaveState, restoreState } = persistenceModule);

    // Override app-level saveState to also call persistence module
    const originalSaveState = saveState;
    saveState = function() {
        originalSaveState();
        persistSaveState?.();
    };

    // Tab switching
    document.getElementById('tab-parts-btn').addEventListener('click', () => {
        document.getElementById('panel-body').style.display   = '';
        document.getElementById('scene-panel').style.display  = 'none';
        document.getElementById('tab-parts-btn').classList.add('active');
        document.getElementById('tab-scene-btn').classList.remove('active');
        document.getElementById('layout-btn').style.display   = '';
        const anyHidden = [...partMap.values()].some(e => !e.visible);
        document.getElementById('show-all-btn').style.display = anyHidden ? '' : 'none';
        // update part-count visibility
        document.getElementById('part-count').style.display   = '';
    });
    document.getElementById('tab-scene-btn').addEventListener('click', () => {
        document.getElementById('panel-body').style.display   = 'none';
        document.getElementById('scene-panel').style.display  = '';
        document.getElementById('tab-scene-btn').classList.add('active');
        document.getElementById('tab-parts-btn').classList.remove('active');
        document.getElementById('layout-btn').style.display   = 'none';
        document.getElementById('show-all-btn').style.display = 'none';
        document.getElementById('part-count').style.display   = 'none';
    });

    document.getElementById('sp-copy-code-btn').addEventListener('click', () => {
        navigator.clipboard.writeText(sceneModule.generateSceneCode()).then(() => showToast('Scene code copied!'));
    });

    // Auto-reload last opened file on page open
    loadLastFileFromDB();
};  // end MaterialMapperApp
