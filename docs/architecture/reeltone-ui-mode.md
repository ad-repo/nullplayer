# Reeltone UI Mode Decision

Reeltone is a distinct `PlayerUIMode`, not an Original skin and not a Winamp Modern (`.wal`)
container. `ReeltoneSkinEngine` owns archive validation, installation identity, selection, and
resource access. `ReeltoneSurfaceCoordinator` owns the manifest-created main surface and dynamic
panel topology. Existing Original functionality is reused only through content-host contracts or
fallback auxiliary controllers.

Authored coordinates use a top-left origin. One authored pixel equals one AppKit point at 100%
UI Size; AppKit backing scale supplies Retina pixels. Conversion into bottom-left AppKit geometry
happens at the surface boundary and is shared by painting, layout, hit testing, and accessibility.

All Reeltone presentation state lives in the `com.nullplayer.app.reeltone` defaults suite and is
scoped to the validated installation identity. Session geometry additionally requires an exact
Reeltone skin-identity match. Compact Mode and Compact Window are intentionally unavailable in
Reeltone mode; switching into Reeltone exits either compact presentation before rebuilding.

The archive/model layer has no AppKit dependency. Shared `App/` changes are capability-gated seams;
substantive behavior remains under `Reeltone/` and `Windows/Reeltone/`.
