'use strict';

window.MaterialMapperShellModule = function ({
    loadBuffer,
    importFromCode,
    getPartMap,
    getMaterialsModule,
    getSceneModule,
    saveState,
    showToast,
}) {
    function bindHeaderMenus() {
        const menus = [...document.querySelectorAll('[data-header-menu]')];

        function closeMenu(menu) {
            const button = menu?.querySelector('.header-menu-btn');
            const popover = menu?.querySelector('.header-menu-popover');
            if (!button || !popover) return;
            button.setAttribute('aria-expanded', 'false');
            popover.hidden = true;
        }

        function openMenu(menu) {
            menus.forEach((entry) => {
                if (entry !== menu) closeMenu(entry);
            });
            const button = menu?.querySelector('.header-menu-btn');
            const popover = menu?.querySelector('.header-menu-popover');
            if (!button || !popover) return;
            button.setAttribute('aria-expanded', 'true');
            popover.hidden = false;
        }

        menus.forEach((menu) => {
            const button = menu.querySelector('.header-menu-btn');
            const popover = menu.querySelector('.header-menu-popover');
            if (!button || !popover) return;

            closeMenu(menu);

            button.addEventListener('click', (event) => {
                event.stopPropagation();
                const isOpen = button.getAttribute('aria-expanded') === 'true';
                if (isOpen) {
                    closeMenu(menu);
                    return;
                }
                openMenu(menu);
            });

            popover.addEventListener('click', (event) => {
                const item = event.target.closest('.header-menu-item');
                if (!item || item.disabled) return;
                closeMenu(menu);
            });
        });

        document.addEventListener('click', (event) => {
            menus.forEach((menu) => {
                if (menu.contains(event.target)) return;
                closeMenu(menu);
            });
        });

        document.addEventListener('keydown', (event) => {
            if (event.key !== 'Escape') return;
            menus.forEach(closeMenu);
        });
    }

    function getLayoutElements() {
        return {
            panelBody: document.getElementById('panel-body'),
            layoutBtn: document.getElementById('layout-btn'),
            editorSide: document.getElementById('editor-side'),
            panelEl: document.getElementById('panel'),
        };
    }

    function syncLayoutButton(isSide) {
        const { layoutBtn } = getLayoutElements();
        if (!layoutBtn) return;
        layoutBtn.title = isSide ? 'Switch to stacked layout' : 'Switch to side-by-side layout';
        layoutBtn.textContent = isSide ? '⊟' : '⊞';
    }

    function getLayoutState() {
        const { panelBody, editorSide, panelEl } = getLayoutElements();
        const partSortSelect = document.getElementById('part-sort-select');
        return {
            mode: panelBody?.classList.contains('side-by-side') ? 'side-by-side' : 'stacked',
            panelWidth: panelEl?.style.width || '',
            editorWidth: editorSide?.style.width || '',
            editorHeight: editorSide?.style.height || '',
            partSort: partSortSelect?.value || 'name-asc',
        };
    }

    function restoreLayoutState(savedLayout) {
        if (!savedLayout) return;

        const { panelBody, editorSide, panelEl } = getLayoutElements();
        const partSortSelect = document.getElementById('part-sort-select');
        if (!panelBody || !editorSide || !panelEl) return;

        const isSide = savedLayout.mode === 'side-by-side';
        panelBody.classList.toggle('side-by-side', isSide);
        syncLayoutButton(isSide);

        panelEl.style.width = savedLayout.panelWidth || '';
        editorSide.style.width = '';
        editorSide.style.height = '';
        editorSide.style.flex = '';

        if (isSide) {
            editorSide.style.width = savedLayout.editorWidth || '';
            if (savedLayout.editorWidth) editorSide.style.flex = 'none';
        } else {
            editorSide.style.height = savedLayout.editorHeight || '';
        }

        if (partSortSelect && savedLayout.partSort) {
            partSortSelect.value = savedLayout.partSort;
        }
    }

    function bindFileLoading() {
        const fileInput = document.getElementById('file-input');
        const openModelBtn = document.getElementById('import-open-model-btn');
        const viewerPane = document.getElementById('viewer-pane');
        const dropOverlay = document.getElementById('drop-overlay');

        openModelBtn?.addEventListener('click', () => fileInput.click());

        fileInput.addEventListener('change', (event) => {
            const file = event.target.files[0];
            if (!file) return;
            file.arrayBuffer().then((buffer) => loadBuffer(buffer, file.name));
            event.target.value = '';
        });

        viewerPane.addEventListener('dragover', (event) => {
            event.preventDefault();
            dropOverlay.classList.add('drag-active');
        });
        viewerPane.addEventListener('dragleave', () => dropOverlay.classList.remove('drag-active'));
        viewerPane.addEventListener('drop', (event) => {
            event.preventDefault();
            dropOverlay.classList.remove('drag-active');
            const file = event.dataTransfer.files[0];
            if (file) file.arrayBuffer().then((buffer) => loadBuffer(buffer, file.name));
        });
        dropOverlay.addEventListener('click', () => fileInput.click());
    }

    function bindModals() {
        const codeModal = document.getElementById('code-modal');
        const exportCodeBtn = document.getElementById('export-code-action-btn');
        const codeModalClose = document.getElementById('code-modal-close');
        const importModal = document.getElementById('import-modal');
        const importCodeBtn = document.getElementById('import-code-action-btn');
        const importMaterialsBtn = document.getElementById('import-materials-action-btn');
        const importModalClose = document.getElementById('import-modal-close');
        const importApplyBtn = document.getElementById('import-apply-btn');
        const importFileBtn = document.getElementById('import-file-btn');
        const importFileInput = document.getElementById('import-file-input');
        const importTextarea = document.getElementById('import-textarea');

        const applyImportText = (text) => {
            const source = text.trim();
            if (!source) return;
            importTextarea.value = source;
            const { matCount, ruleCount } = importFromCode(source);
            importModal.classList.add('hidden');
            showToast(`Imported: ${matCount} material${matCount !== 1 ? 's' : ''}, ${ruleCount} rule${ruleCount !== 1 ? 's' : ''}`);
        };

        exportCodeBtn?.addEventListener('click', () => codeModal.classList.remove('hidden'));
        codeModalClose.addEventListener('click', () => codeModal.classList.add('hidden'));
        codeModal.addEventListener('click', (event) => {
            if (event.target === codeModal) codeModal.classList.add('hidden');
        });

        importCodeBtn?.addEventListener('click', () => {
            importTextarea.value = '';
            importModal.classList.remove('hidden');
            setTimeout(() => importTextarea.focus(), 50);
        });
        importMaterialsBtn?.addEventListener('click', () => {
            importFileInput.value = '';
            importFileInput.click();
        });
        importModalClose.addEventListener('click', () => importModal.classList.add('hidden'));
        importModal.addEventListener('click', (event) => {
            if (event.target === importModal) importModal.classList.add('hidden');
        });

        importApplyBtn.addEventListener('click', () => {
            applyImportText(importTextarea.value);
        });

        importFileBtn.addEventListener('click', () => {
            importFileInput.value = '';
            importFileInput.click();
        });

        importFileInput.addEventListener('change', async (event) => {
            const file = event.target.files?.[0];
            if (!file) return;

            try {
                const text = await file.text();
                applyImportText(text);
            } catch (error) {
                console.error('[Material Mapper] File import failed:', error);
                showToast(`Import failed: ${error?.message ?? String(error)}`);
            } finally {
                importFileInput.value = '';
            }
        });

        document.addEventListener('keydown', (event) => {
            if (event.key !== 'Escape') return;
            codeModal.classList.add('hidden');
            importModal.classList.add('hidden');
        });
    }

    function bindPanelLayout() {
        const panelBody = document.getElementById('panel-body');
        const layoutBtn = document.getElementById('layout-btn');
        const editorSide = document.getElementById('editor-side');
        const panelEl = document.getElementById('panel');
        const panelResizeHandle = document.getElementById('panel-resize-handle');
        const resizeHandle = document.getElementById('resize-handle');

        layoutBtn.addEventListener('click', () => {
            const isSide = panelBody.classList.toggle('side-by-side');
            syncLayoutButton(isSide);
            editorSide.style.height = '';
            editorSide.style.width = '';
            editorSide.style.flex = '';
            saveState?.();
        });

        panelResizeHandle.addEventListener('pointerdown', (event) => {
            event.preventDefault();
            panelResizeHandle.classList.add('dragging');
            panelResizeHandle.setPointerCapture(event.pointerId);

            const startX = event.clientX;
            const startW = panelEl.offsetWidth;
            const layoutW = panelEl.parentElement.offsetWidth;
            const min = 200;
            const max = layoutW * 0.70;

            function onMove(moveEvent) {
                const newW = Math.max(min, Math.min(max, startW - (moveEvent.clientX - startX)));
                panelEl.style.width = newW + 'px';
            }

            function onUp() {
                panelResizeHandle.classList.remove('dragging');
                panelResizeHandle.removeEventListener('pointermove', onMove);
                panelResizeHandle.removeEventListener('pointerup', onUp);
                saveState?.();
            }

            panelResizeHandle.addEventListener('pointermove', onMove);
            panelResizeHandle.addEventListener('pointerup', onUp);
        });

        resizeHandle.addEventListener('pointerdown', (event) => {
            event.preventDefault();
            resizeHandle.classList.add('dragging');
            resizeHandle.setPointerCapture(event.pointerId);

            const isSide = panelBody.classList.contains('side-by-side');
            const startPos = isSide ? event.clientX : event.clientY;
            const startSize = isSide ? editorSide.offsetWidth : editorSide.offsetHeight;
            const panelSize = isSide ? panelBody.offsetWidth : panelBody.offsetHeight;
            const min = 80;
            const maxFrac = 0.85;

            function onMove(moveEvent) {
                const delta = isSide ? (startPos - moveEvent.clientX) : (startPos - moveEvent.clientY);
                const newSize = Math.max(min, Math.min(panelSize * maxFrac, startSize + delta));
                if (isSide) {
                    editorSide.style.flex = 'none';
                    editorSide.style.width = newSize + 'px';
                } else {
                    editorSide.style.height = newSize + 'px';
                }
            }

            function onUp() {
                resizeHandle.classList.remove('dragging');
                resizeHandle.removeEventListener('pointermove', onMove);
                resizeHandle.removeEventListener('pointerup', onUp);
                saveState?.();
            }

            resizeHandle.addEventListener('pointermove', onMove);
            resizeHandle.addEventListener('pointerup', onUp);
        });
    }

    function bindTabsAndScene() {
        const tabPartsBtn = document.getElementById('tab-parts-btn');
        const tabMaterialsBtn = document.getElementById('tab-materials-btn');
        const tabSceneBtn = document.getElementById('tab-scene-btn');
        const panelBody = document.getElementById('panel-body');
        const partsSide = document.querySelector('.parts-side');
        const materialsSide = document.getElementById('materials-side');
        const scenePanel = document.getElementById('scene-panel');
        const layoutBtn = document.getElementById('layout-btn');
        const showAllBtn = document.getElementById('show-all-btn');
        const partCount = document.getElementById('part-count');
        const copySceneCodeBtn = document.getElementById('sp-copy-code-btn');

        function activatePartsTab() {
            panelBody.style.display = '';
            scenePanel.style.display = 'none';
            if (partsSide) partsSide.style.display = '';
            if (materialsSide) materialsSide.style.display = 'none';
            tabPartsBtn.classList.add('active');
            tabMaterialsBtn?.classList.remove('active');
            tabSceneBtn.classList.remove('active');
            layoutBtn.style.display = '';
            const anyHidden = [...getPartMap().values()].some((entry) => !entry.visible);
            showAllBtn.style.display = anyHidden ? '' : 'none';
            partCount.style.display = '';
            getMaterialsModule?.()?.syncSelectionEditor?.();
        }

        function activateMaterialsTab() {
            panelBody.style.display = '';
            scenePanel.style.display = 'none';
            if (partsSide) partsSide.style.display = 'none';
            if (materialsSide) materialsSide.style.display = '';
            tabPartsBtn.classList.remove('active');
            tabMaterialsBtn?.classList.add('active');
            tabSceneBtn.classList.remove('active');
            layoutBtn.style.display = '';
            showAllBtn.style.display = 'none';
            partCount.style.display = 'none';
            getMaterialsModule?.()?.activateMaterialManager?.();
        }

        tabPartsBtn.addEventListener('click', () => {
            activatePartsTab();
        });

        tabMaterialsBtn?.addEventListener('click', () => {
            activateMaterialsTab();
        });

        tabSceneBtn.addEventListener('click', () => {
            panelBody.style.display = 'none';
            scenePanel.style.display = '';
            tabSceneBtn.classList.add('active');
            tabPartsBtn.classList.remove('active');
            tabMaterialsBtn?.classList.remove('active');
            layoutBtn.style.display = 'none';
            showAllBtn.style.display = 'none';
            partCount.style.display = 'none';
        });

        copySceneCodeBtn.addEventListener('click', () => {
            const sceneModule = getSceneModule();
            if (!sceneModule) return;
            navigator.clipboard.writeText(sceneModule.generateSceneCode()).then(() => showToast('Scene and preset code copied!'));
        });
    }

    function onModelLoaded(fileName) {
        const exportGlbBtn = document.getElementById('export-glb-btn');
        document.getElementById('drop-overlay').classList.add('hidden');
        document.getElementById('search-input').value = '';
        document.getElementById('zfix-btn').style.display = '';
        if (exportGlbBtn) exportGlbBtn.disabled = false;
        document.title = `Material Mapper — ${fileName}`;
    }

    function init() {
        bindHeaderMenus();
        bindFileLoading();
        bindModals();
        bindPanelLayout();
        bindTabsAndScene();
    }

    return {
        init,
        getLayoutState,
        onModelLoaded,
        restoreLayoutState,
    };
};