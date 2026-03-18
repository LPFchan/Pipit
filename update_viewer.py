import shutil

# Sync the canonical viewer.html from assets/ into the iOS Resources bundle.
# FobViewer.swift loads via loadFileURL(url, allowingReadAccessTo: resourceDir),
# so Uguisu.glb is referenced by its relative filename — no URL-scheme rewrite needed.
shutil.copy("assets/viewer.html", "iosApp/iosApp/Resources/viewer.html")
print("Synced assets/viewer.html → iosApp/iosApp/Resources/viewer.html")
