'use strict';

/**
 * Material Mapper Persistence Module
 * 
 * Encapsulates state saving/loading via:
 * - IndexedDB: caches last-opened file without size limits
 * - LocalStorage: per-file session state (matProps, visibility, camera, etc.)
 * 
 * Module Factory: window.MaterialMapperPersistenceModule
 * Dependencies passed via constructor:
 *   - partMap: Map of displayName → part entries
 *   - matProps: material property object
 *   - loadedFileName: string (current model filename)
 *   - loadedModel: THREE.js model or null
 *   - camera: THREE.js camera
 *   - controls: OrbitControls
 *   - sceneState: scene module state object
 *   - saveCallback: called after state is saved
 *   - restoreCallback: called after state is restored
 */
window.MaterialMapperPersistenceModule = function ({
    loadBuffer,
    partMap,
    matProps,
    MAT_OBJ,
    loadedFileName,
    loadedModel,
    isOrtho,
    hudState,
    shellState,
    materialsState,
    camera,
    controls,
    sceneState,
    groundMesh,
    THREE,
    requestRender,
    showToast,
    importFromCode,
}) {
    const resolve = (valueOrGetter) => (typeof valueOrGetter === 'function' ? valueOrGetter() : valueOrGetter);
    let writesSuspended = false;

    // ─────────────────────────────────────────────────────────────
    // IndexedDB: store last-opened file (no size limit)
    // ─────────────────────────────────────────────────────────────
    const IDB_NAME  = 'material-mapper-files';
    const IDB_STORE = 'files';

    function openIDB() {
        return new Promise((res, rej) => {
            const req = indexedDB.open(IDB_NAME, 1);
            req.onupgradeneeded = e => e.target.result.createObjectStore(IDB_STORE);
            req.onsuccess = e => res(e.target.result);
            req.onerror   = e => rej(e.target.error);
        });
    }

    function saveLastFileToDB(fileName, buffer) {
        openIDB().then(db => {
            const tx = db.transaction(IDB_STORE, 'readwrite');
            tx.objectStore(IDB_STORE).put({ name: fileName, buffer: buffer.slice(0) }, 'last');
        }).catch(e => console.warn('[IDB] save failed', e));
    }

    function loadLastFileFromDB() {
        openIDB().then(db => {
            const tx  = db.transaction(IDB_STORE, 'readonly');
            const req = tx.objectStore(IDB_STORE).get('last');
            req.onsuccess = e => {
                const data = e.target.result;
                if (data?.buffer && data?.name) loadBuffer(data.buffer, data.name);
            };
        }).catch(e => console.warn('[IDB] load failed', e));
    }

    // ─────────────────────────────────────────────────────────────
    // localStorage: per-file session state
    // ─────────────────────────────────────────────────────────────
    const STORAGE_KEY = 'material-mapper-v1';

    function captureState() {
        const currentMatProps = resolve(matProps);
        const currentLoadedModel = resolve(loadedModel);
        const currentIsOrtho = resolve(isOrtho);
        const currentHudState = resolve(hudState);
        const currentShellState = resolve(shellState);
        const currentMaterialsState = resolve(materialsState);
        const currentSceneState = resolve(sceneState);

        if (partMap.size === 0 || !currentMatProps) return null;

        const assignments = {};
        const visibility = {};
        for (const [name, entry] of partMap) {
            assignments[name] = entry.assignedKey;
            if (!entry.visible) visibility[name] = false;
        }

        return {
            matProps: JSON.parse(JSON.stringify(currentMatProps)),
            materialsState: currentMaterialsState ? JSON.parse(JSON.stringify(currentMaterialsState)) : null,
            assignments,
            visibility,
            camera: {
                position: { x: camera.position.x, y: camera.position.y, z: camera.position.z },
                target: { x: controls.target.x, y: controls.target.y, z: controls.target.z },
                fov: camera.fov,
                isOrtho: !!currentIsOrtho,
            },
            modelRotation: currentLoadedModel ? {
                x: THREE.MathUtils.radToDeg(currentLoadedModel.rotation.x),
                y: THREE.MathUtils.radToDeg(currentLoadedModel.rotation.y),
                z: THREE.MathUtils.radToDeg(currentLoadedModel.rotation.z),
            } : null,
            modelPosition: currentLoadedModel ? {
                x: currentLoadedModel.position.x,
                y: currentLoadedModel.position.y,
                z: currentLoadedModel.position.z,
            } : null,
            hudState: currentHudState ? JSON.parse(JSON.stringify(currentHudState)) : null,
            shellState: currentShellState ? JSON.parse(JSON.stringify(currentShellState)) : null,
            sceneState: currentSceneState ? JSON.parse(JSON.stringify(currentSceneState)) : null,
        };
    }

    function saveState() {
        if (writesSuspended) return;

        const currentFileName = resolve(loadedFileName);
        const state = captureState();
        if (!currentFileName || !state) return;
        try {
            const all = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}');
            all[currentFileName] = state;
            localStorage.setItem(STORAGE_KEY, JSON.stringify(all));
        } catch (e) { console.warn('[State] save failed', e); }
    }

    function suspendWrites() {
        writesSuspended = true;
    }

    function resumeWrites() {
        writesSuspended = false;
    }

    // ─────────────────────────────────────────────────────────────
    // Import from code — parse generated code and restore state
    // ─────────────────────────────────────────────────────────────
    function _importFromCode(text) {
        // This is a wrapper; actual importFromCode should be passed from app.js
        // which has access to the UI update functions
        if (typeof importFromCode === 'function') {
            return importFromCode(text);
        }
        return { matCount: 0, ruleCount: 0 };
    }

    // ─────────────────────────────────────────────────────────────
    // Restore persisted state from localStorage
    // ─────────────────────────────────────────────────────────────
    function applyStateSnapshot(saved, callbacks) {
        const currentMatProps = resolve(matProps);
        const currentMAT_OBJ = resolve(MAT_OBJ);
        const currentLoadedModel = resolve(loadedModel);
        const {
            applyMaterials,
            buildPartsUI,
            buildEditor,
            syncShowAllBtn,
            toggleOrtho,
            setIsOrtho,
            setHudXYZ,
            applyModelRotationDeg,
            restoreHudState,
            syncOrbitTarget,
            restoreLayoutState,
            restoreMaterialState,
            mergeSceneState,
            applySceneState,
            syncScenePanel,
        } = callbacks || {};

        if (!saved) return false;

        try {
            const savedMaterialsState = saved.materialsState ?? (saved.matProps ? { matProps: saved.matProps } : null);

            // Restore materials registry and live Three.js material objects
            if (savedMaterialsState && restoreMaterialState) {
                restoreMaterialState(savedMaterialsState);
            } else {
                for (const [key, props] of Object.entries(saved.matProps ?? {})) {
                    if (!currentMatProps || !(key in currentMatProps)) continue;
                    Object.assign(currentMatProps[key], props);
                    const mat = currentMAT_OBJ?.[key];
                    if (!mat) continue;
                    const p = currentMatProps[key];
                    mat.color.set(p.color);
                    mat.emissive.set(p.emissive);
                    mat.emissiveIntensity = p.emissiveIntensity;
                    mat.roughness         = p.roughness;
                    mat.metalness         = p.metalness;
                    mat.transmission      = p.transmission;
                    mat.thickness         = p.thickness;
                    mat.ior               = p.ior;
                    mat.opacity           = p.opacity;
                    mat.transparent          = p.transparent;
                    mat.toneMapped           = p.toneMapped;
                    mat.side                 = p.side === 'Double' ? THREE.DoubleSide : THREE.FrontSide;
                    mat.polygonOffset        = p.polygonOffset        ?? false;
                    mat.polygonOffsetFactor  = p.polygonOffsetFactor  ?? 0;
                    mat.polygonOffsetUnits   = p.polygonOffsetUnits   ?? 0;
                    mat.needsUpdate          = true;
                }
            }

            // Restore per-part assignments + visibility
            for (const [name, entry] of partMap) {
                const key = saved.assignments?.[name];
                if (key) entry.assignedKey = key;
                if (saved.visibility && name in saved.visibility) {
                    entry.visible = saved.visibility[name];
                    entry.meshes.forEach(m => { m.visible = saved.visibility[name]; });
                }
            }

            // Restore camera if callback provided
            if (callbacks && saved.camera) {
                const c = saved.camera;
                if (c.position) camera.position.set(c.position.x, c.position.y, c.position.z);
                if (c.target)   controls.target.set(c.target.x, c.target.y, c.target.z);
                if (c.fov)      { camera.fov = c.fov; camera.updateProjectionMatrix(); }
                controls.update();
                if (setHudXYZ) {
                    setHudXYZ('hud-pos-x', 'hud-pos-y', 'hud-pos-z', camera.position);
                    setHudXYZ('hud-tgt-x', 'hud-tgt-y', 'hud-tgt-z', controls.target);
                }
                if (c.isOrtho !== undefined) {
                    if (setIsOrtho) {
                        setIsOrtho(c.isOrtho);
                    } else if (toggleOrtho) {
                        toggleOrtho(c.isOrtho);
                    }
                }
            }

            // Restore model rotation if callback provided
            if (callbacks && saved.modelRotation && applyModelRotationDeg) {
                const r = saved.modelRotation;
                applyModelRotationDeg(r.x, r.y, r.z, false);
            }

            // Restore model position
            if (callbacks && saved.modelPosition && currentLoadedModel) {
                const p = saved.modelPosition;
                currentLoadedModel.position.set(p.x ?? currentLoadedModel.position.x, p.y ?? currentLoadedModel.position.y, p.z ?? currentLoadedModel.position.z);
                currentLoadedModel.updateMatrixWorld(true);
                const modelBox = new THREE.Box3().setFromObject(currentLoadedModel);
                if (groundMesh) groundMesh.position.y = modelBox.min.y - 0.008;
                if (syncOrbitTarget) syncOrbitTarget();
            }

            if (currentLoadedModel && groundMesh) {
                currentLoadedModel.updateMatrixWorld(true);
                groundMesh.position.y = new THREE.Box3().setFromObject(currentLoadedModel).min.y - 0.008;
            }

            // Restore scene state if callback provided
            if (callbacks && saved.sceneState) {
                if (mergeSceneState) mergeSceneState(saved.sceneState);
                if (applySceneState) applySceneState();
                if (syncScenePanel) syncScenePanel();
            }

            if (callbacks && saved.hudState && restoreHudState) {
                restoreHudState(saved.hudState);
            }

            if (callbacks && saved.shellState && restoreLayoutState) {
                restoreLayoutState(saved.shellState);
            }

            if (applyMaterials) applyMaterials();
            if (buildPartsUI) buildPartsUI();
            if (syncShowAllBtn) syncShowAllBtn();
            if (buildEditor) buildEditor(null);
            requestRender?.();

            return true;
        } catch (e) {
            console.warn('[State] restore failed', e);
            return false;
        }
    }

    function restoreState(fileName, callbacks) {
        try {
            const all = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}');
            const saved = all[fileName];
            if (!saved) return false;
            return applyStateSnapshot(saved, callbacks);
        } catch (e) {
            console.warn('[State] restore failed', e);
            return false;
        }
    }

    // ─────────────────────────────────────────────────────────────
    // Public API
    // ─────────────────────────────────────────────────────────────
    return {
        // IDB file cache
        saveLastFileToDB,
        loadLastFileFromDB,

        // Local storage state
        captureState,
        applyState: applyStateSnapshot,
        saveState,
        restoreState,
        suspendWrites,
        resumeWrites,

        // Import/export
        importFromCode: _importFromCode,
    };
};
