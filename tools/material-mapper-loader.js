'use strict';

window.MaterialMapperLoaderModule = function ({
    THREE,
    GLTFLoader,
    scene,
    camera,
    groundMesh,
    partMap,
    getLoadedModel,
    setLoadedModel,
    setLoadedFileName,
    resetSelection,
    guessKey,
    fitCameraToModel,
    applyMaterials,
    buildPartsUI,
    syncShowAllBtn,
    buildEditor,
    syncEditor,
    updateCode,
    getMatProps,
    getMAT_OBJ,
    saveLastFileToDB,
    restoreState,
    getRestoreCallbacks,
    onModelLoaded,
    saveState,
    showToast,
}) {
    const loader = new GLTFLoader();

    function syncMaterialObject(mat, props) {
        if (!mat || !props) return;
        mat.color.set(props.color);
        mat.emissive.set(props.emissive);
        mat.emissiveIntensity = props.emissiveIntensity;
        mat.roughness = props.roughness;
        mat.metalness = props.metalness;
        mat.transmission = props.transmission;
        mat.thickness = props.thickness;
        mat.ior = props.ior;
        mat.opacity = props.opacity;
        mat.transparent = props.transparent;
        mat.toneMapped = props.toneMapped;
        mat.side = props.side === 'Double' ? THREE.DoubleSide : THREE.FrontSide;
        mat.polygonOffset = props.polygonOffset ?? false;
        mat.polygonOffsetFactor = props.polygonOffsetFactor ?? 0;
        mat.polygonOffsetUnits = props.polygonOffsetUnits ?? 0;
        mat.needsUpdate = true;
    }

    function parseImportedValue(rawValue) {
        const value = String(rawValue || '').trim();
        if (!value) return null;
        if (/^0x[0-9a-f]+$/i.test(value)) return '#' + value.slice(2);
        if (value === 'THREE.DoubleSide') return 'Double';
        if (value === 'THREE.FrontSide') return 'Front';
        if (value === 'true') return true;
        if (value === 'false') return false;
        if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
            return value.slice(1, -1);
        }
        const num = parseFloat(value);
        return Number.isFinite(num) ? num : value;
    }

    function decodeQuotedString(token) {
        return token
            .replace(/\\'/g, "'")
            .replace(/\\\\/g, '\\');
    }

    function importFromCode(text) {
        if (!text || typeof text !== 'string') return { matCount: 0, ruleCount: 0 };

        const matProps = getMatProps?.();
        const MAT_OBJ = getMAT_OBJ?.();
        if (!matProps || !MAT_OBJ) return { matCount: 0, ruleCount: 0 };

        const source = text.replace(/^\s*\/\/.*$/gm, '');
        let matCount = 0;
        let ruleCount = 0;

        try {
            const matRegex = /const\s+(\w+)\s*=\s*new\s+THREE\.\w+\s*\(\s*\{([\s\S]*?)\}\s*\);?/g;
            let matMatch;
            while ((matMatch = matRegex.exec(source)) !== null) {
                const matKey = matMatch[1];
                const propsBlock = matMatch[2];
                if (!(matKey in matProps)) continue;

                const nextProps = matProps[matKey];
                const propRegex = /(\w+)\s*:\s*([^,\n]+)\s*,?/g;
                let propMatch;
                let changed = false;
                while ((propMatch = propRegex.exec(propsBlock)) !== null) {
                    const propKey = propMatch[1];
                    if (!(propKey in nextProps)) continue;
                    nextProps[propKey] = parseImportedValue(propMatch[2]);
                    changed = true;
                }

                if (changed) {
                    syncMaterialObject(MAT_OBJ[matKey], nextProps);
                    matCount++;
                }
            }

            const rulesMatch = source.match(/const\s+MATERIAL_RULES\s*=\s*\[([\s\S]*?)\];?/);
            if (rulesMatch) {
                const ruleRegex = /\{\s*match:\s*('(?:[^'\\]|\\.)*'|\/\.\*\/)\s*,\s*mat:\s*(\w+)\s*\}/g;
                let ruleMatch;
                while ((ruleMatch = ruleRegex.exec(rulesMatch[1])) !== null) {
                    const matchToken = ruleMatch[1];
                    const matKey = ruleMatch[2];
                    if (matchToken.startsWith('/')) continue;
                    const partName = decodeQuotedString(matchToken.slice(1, -1));
                    const entry = partMap.get(partName);
                    if (!entry) continue;
                    entry.assignedKey = matKey;
                    ruleCount++;
                }
            }

            applyMaterials();
            buildPartsUI();
            syncShowAllBtn();
            syncEditor();
            updateCode();
            saveState();
            return { matCount, ruleCount };
        } catch (error) {
            console.error('[Material Mapper] Import parse error:', error);
            showToast(`Import failed: ${error?.message ?? String(error)}`);
            return { matCount: 0, ruleCount: 0 };
        }
    }

    function loadBuffer(buffer, fileName) {
        loader.parse(buffer, '', (gltf) => {
            const previousModel = getLoadedModel?.();
            if (previousModel) scene.remove(previousModel);

            partMap.clear();
            resetSelection();

            const model = gltf.scene;
            const groupMap = new Map();

            model.traverse((child) => {
                if (!child.isMesh) return;

                const parent = child.parent;
                const sceneRoot = parent === model || parent === gltf.scene || !parent;
                const ownName = child.name?.trim() || '';
                const parentName = (!sceneRoot && parent.name?.trim()) || '';

                let groupKey;
                let rawName;
                if (!sceneRoot && parentName) {
                    groupKey = parent.uuid;
                    rawName = parentName;
                } else {
                    groupKey = (sceneRoot ? (parent?.uuid ?? 'root') : parent.uuid) + '|' + (ownName || child.uuid);
                    rawName = ownName;
                }

                if (!groupMap.has(groupKey)) {
                    groupMap.set(groupKey, { rawName, meshes: [], origMats: [] });
                }

                const group = groupMap.get(groupKey);
                group.meshes.push(child);
                group.origMats.push(child.material);
            });

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
                    origName: rawName,
                    assignedKey: guessKey(rawName),
                    visible: true,
                });
            }

            const box = new THREE.Box3().setFromObject(model);
            const size = box.getSize(new THREE.Vector3());
            const center = box.getCenter(new THREE.Vector3());
            const maxDim = Math.max(size.x, size.y, size.z) || 1;
            const scale = 1.0 / maxDim;
            model.scale.setScalar(scale);
            model.position.sub(center.multiplyScalar(scale));

            scene.add(model);
            setLoadedModel(model);
            setLoadedFileName(fileName);

            fitCameraToModel();
            const hudFovEl = document.getElementById('hud-fov');
            if (hudFovEl) hudFovEl.value = Math.round(camera.fov);

            model.traverse((child) => {
                if (child.isMesh && !child.userData.isOutline) {
                    child.castShadow = true;
                    child.receiveShadow = true;
                }
            });

            const modelBox = new THREE.Box3().setFromObject(model);
            groundMesh.position.y = modelBox.min.y - 0.008;

            onModelLoaded?.(fileName);
            saveLastFileToDB?.(fileName, buffer);

            const didRestore = restoreState?.(fileName, getRestoreCallbacks?.());
            if (!didRestore) {
                applyMaterials();
                buildPartsUI();
                syncShowAllBtn();
                syncEditor();
            } else {
                showToast('Session restored');
            }
        }, (error) => {
            console.error('[Material Mapper] GLTF parse error:', error);
            alert('Could not load model:\n' + (error?.message ?? String(error)));
        });
    }

    return {
        loadBuffer,
        importFromCode,
    };
};