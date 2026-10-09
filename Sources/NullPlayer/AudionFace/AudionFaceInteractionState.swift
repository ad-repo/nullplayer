import Foundation

/// The pointer's effect on the buttons. Disabling that follows from playback (stop with no track)
/// is the scene's rule; `disabled` holds only what the window imposes, such as the volume button
/// while its slider is open.
struct AudionFaceInteractionState: Equatable {
    var hovered: AudionFace.ButtonRole?
    var pressed: AudionFace.ButtonRole?
    var disabled: Set<AudionFace.ButtonRole> = []
}
