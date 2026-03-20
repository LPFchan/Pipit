'use strict';

window.MaterialMapperToolsModule = function ({
    THREE,
    GLTFExporter,
    getLoadedModel,
    getLoadedFileName,
    partMap,
    getMatProps,
    setProp,
    syncEditor,
    requestRender,
    showToast,
}) {
    function exportGLB() {
        const loadedModel = getLoadedModel?.();
        const loadedFileName = getLoadedFileName?.();
        if (!loadedModel || !loadedFileName) return;

        const outlines = [];
        loadedModel.traverse((child) => {
            if (child.userData.isOutline) {
                outlines.push(child);
                child.visible = false;
            }
        });

        const exporter = new GLTFExporter();
        requestRender?.();
        exporter.parse(loadedModel, (glb) => {
            outlines.forEach((child) => { child.visible = true; });
            const base = loadedFileName.replace(/\.[^.]+$/, '');
            const blob = new Blob([glb], { type: 'model/gltf-binary' });
            const url = URL.createObjectURL(blob);
            const anchor = document.createElement('a');
            anchor.href = url;
            anchor.download = base + '_visible.glb';
            anchor.click();
            URL.revokeObjectURL(url);
            showToast('GLB exported!');
        }, (error) => {
            outlines.forEach((child) => { child.visible = true; });
            console.error('[Export GLB]', error);
            showToast('Export failed — see console');
        }, { binary: true, onlyVisible: true });
    }

    function autoFixZFighting() {
        const loadedModel = getLoadedModel?.();
        const matProps = getMatProps?.();
        if (!loadedModel || !matProps) return;

        loadedModel.updateMatrixWorld(true);

        const items = [];
        loadedModel.traverse((child) => {
            if (!child.isMesh || child.userData.isOutline || !child.geometry) return;
            child.geometry.computeBoundingBox();
            const box = child.geometry.boundingBox.clone().applyMatrix4(child.matrixWorld);
            items.push({ mesh: child, box });
        });

        const meshToPartName = new Map();
        for (const [name, entry] of partMap) {
            for (const mesh of entry.meshes) meshToPartName.set(mesh.uuid, name);
        }

        const pairs = [];
        const seenPairs = new Set();
        let sameMaterialPairs = 0;
        let keepPairs = 0;

        console.group('[Z-Fix] Detection pass');
        console.log(`Meshes scanned: ${items.length}`);

        for (let i = 0; i < items.length; i++) {
            for (let j = i + 1; j < items.length; j++) {
                const a = items[i];
                const b = items[j];
                if (!a.box.intersectsBox(b.box)) continue;

                const ix = Math.min(a.box.max.x, b.box.max.x) - Math.max(a.box.min.x, b.box.min.x);
                const iy = Math.min(a.box.max.y, b.box.max.y) - Math.max(a.box.min.y, b.box.min.y);
                const iz = Math.min(a.box.max.z, b.box.max.z) - Math.max(a.box.min.z, b.box.min.z);
                const dims = [ix, iy, iz].sort((x, y) => x - y);
                if (dims[2] < 1e-9 || dims[0] / dims[2] > 0.01) continue;

                const sizeA = a.box.getSize(new THREE.Vector3());
                const sizeB = b.box.getSize(new THREE.Vector3());
                const volA = sizeA.x * sizeA.y * sizeA.z;
                const volB = sizeB.x * sizeB.y * sizeB.z;
                const [winner, loser] = volA <= volB ? [a, b] : [b, a];

                const winName = meshToPartName.get(winner.mesh.uuid);
                const losName = meshToPartName.get(loser.mesh.uuid);
                const winKey = winName ? partMap.get(winName)?.assignedKey : null;
                const losKey = losName ? partMap.get(losName)?.assignedKey : null;

                console.log(`Coplanar pair — dims:[${dims.map((d) => d.toFixed(5)).join(', ')}] ratio:${(dims[0] / dims[2]).toFixed(4)}`, {
                    winner: winName ?? '(unmapped)', winnerMat: winKey ?? '?', volWinner: volA <= volB ? volA : volB,
                    loser: losName ?? '(unmapped)', loserMat: losKey ?? '?', volLoser: volA <= volB ? volB : volA,
                });

                if (!winName || !losName || !winKey || !losKey) continue;
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

        let count = 0;
        for (const key of Object.keys(matProps)) {
            if (matProps[key].polygonOffsetFactor !== 0) setProp(key, 'polygonOffsetFactor', 0);
            if (matProps[key].polygonOffsetUnits !== 0) setProp(key, 'polygonOffsetUnits', 0);
            if (matProps[key].polygonOffset) setProp(key, 'polygonOffset', false);
        }

        const factorSnapshot = {};
        for (const key of Object.keys(matProps)) factorSnapshot[key] = 0;

        console.group('[Z-Fix] Apply pass');
        for (const { winnerKey, loserKey } of pairs) {
            const loserFactor = factorSnapshot[loserKey];
            const neededFactor = loserFactor - 2;

            console.log(`${winnerKey}(snap:${factorSnapshot[winnerKey]}) vs ${loserKey}(snap:${loserFactor}) → setting winner to ${neededFactor}`);

            setProp(winnerKey, 'polygonOffset', true);
            setProp(winnerKey, 'polygonOffsetFactor', neededFactor);
            setProp(winnerKey, 'polygonOffsetUnits', neededFactor);
            count++;
        }
        console.groupEnd();

        syncEditor?.();

        const notes = [
            sameMaterialPairs > 0 ? `${sameMaterialPairs} same-material pair${sameMaterialPairs !== 1 ? 's' : ''} can't be auto-fixed (assign separate materials)` : '',
            keepPairs > 0 ? `${keepPairs} pair${keepPairs !== 1 ? 's' : ''} use _keep material (reassign to fix)` : '',
        ].filter(Boolean).join('; ');

        const noPairs = pairs.length === 0 && sameMaterialPairs === 0 && keepPairs === 0;
        showToast(
            noPairs ? 'No coplanar overlap detected — check console for details' :
            count > 0 ? `Z-fix: updated ${count} material${count !== 1 ? 's' : ''}${notes ? ` · ${notes}` : ''}` :
            `Offsets already correct${notes ? ` · ${notes}` : ''}`
        );
    }

    return {
        exportGLB,
        autoFixZFighting,
    };
};