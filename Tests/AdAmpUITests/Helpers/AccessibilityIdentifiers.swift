import Foundation

/// Centralized accessibility identifiers for UI testing
/// These identifiers are used both in the app (to set identifiers) and in tests (to find elements)
enum AccessibilityIdentifiers {
    
    // MARK: - Main Window
    
    enum MainWindow {
        static let window = "mainWindow"
        
        // Transport controls
        static let playButton = "mainWindow.playButton"
        static let pauseButton = "mainWindow.pauseButton"
        static let stopButton = "mainWindow.stopButton"
        static let previousButton = "mainWindow.previousButton"
        static let nextButton = "mainWindow.nextButton"
        static let ejectButton = "mainWindow.ejectButton"
        
        // Sliders
        static let seekSlider = "mainWindow.seekSlider"
        static let volumeSlider = "mainWindow.volumeSlider"
        static let balanceSlider = "mainWindow.balanceSlider"
        
        // Toggle buttons
        static let shuffleButton = "mainWindow.shuffleButton"
        static let repeatButton = "mainWindow.repeatButton"
        static let eqToggleButton = "mainWindow.eqToggleButton"
        static let playlistToggleButton = "mainWindow.playlistToggleButton"
        
        // Window controls
        static let closeButton = "mainWindow.closeButton"
        static let minimizeButton = "mainWindow.minimizeButton"
        static let shadeButton = "mainWindow.shadeButton"
        
        // Display elements
        static let timeDisplay = "mainWindow.timeDisplay"
        static let currentTime = "mainWindow.currentTime"
        static let trackInfo = "mainWindow.trackInfo"
        static let stereoIndicator = "mainWindow.stereoIndicator"
        static let bitrateDisplay = "mainWindow.bitrateDisplay"
        static let sampleRateDisplay = "mainWindow.sampleRateDisplay"
        static let spectrumAnalyzer = "mainWindow.spectrumAnalyzer"
        static let playbackStatus = "mainWindow.playbackStatus"
        
        // Other
        static let logoButton = "mainWindow.logoButton"
        static let menuButton = "mainWindow.menuButton"
    }
    
    // MARK: - Playlist Window
    
    enum Playlist {
        static let window = "playlistWindow"
        
        // Track list
        static let trackList = "playlist.trackList"
        static let trackCell = "playlist.trackCell"  // Append index: "playlist.trackCell.0"
        
        // Window controls
        static let closeButton = "playlist.closeButton"
        static let shadeButton = "playlist.shadeButton"
        
        // Scrollbar
        static let scrollbar = "playlist.scrollbar"
        
        // Bottom bar buttons
        static let addButton = "playlist.addButton"
        static let removeButton = "playlist.removeButton"
        static let selectButton = "playlist.selectButton"
        static let miscButton = "playlist.miscButton"
        static let listButton = "playlist.listButton"
        
        // Mini transport
        static let miniPreviousButton = "playlist.miniPreviousButton"
        static let miniPlayButton = "playlist.miniPlayButton"
        static let miniPauseButton = "playlist.miniPauseButton"
        static let miniStopButton = "playlist.miniStopButton"
        static let miniNextButton = "playlist.miniNextButton"
        static let miniOpenButton = "playlist.miniOpenButton"
        
        // Info displays
        static let trackCountDisplay = "playlist.trackCountDisplay"
        static let totalTimeDisplay = "playlist.totalTimeDisplay"
        static let playbackTimeDisplay = "playlist.playbackTimeDisplay"
    }
    
    // MARK: - Equalizer Window
    
    enum Equalizer {
        static let window = "equalizerWindow"
        
        // Window controls
        static let closeButton = "equalizer.closeButton"
        static let shadeButton = "equalizer.shadeButton"
        
        // Toggle buttons
        static let onOffButton = "equalizer.onOffButton"
        static let autoButton = "equalizer.autoButton"
        static let presetsButton = "equalizer.presetsButton"
        
        // Sliders
        static let preampSlider = "equalizer.preampSlider"
        static let band60Slider = "equalizer.band60Slider"
        static let band170Slider = "equalizer.band170Slider"
        static let band310Slider = "equalizer.band310Slider"
        static let band600Slider = "equalizer.band600Slider"
        static let band1kSlider = "equalizer.band1kSlider"
        static let band3kSlider = "equalizer.band3kSlider"
        static let band6kSlider = "equalizer.band6kSlider"
        static let band12kSlider = "equalizer.band12kSlider"
        static let band14kSlider = "equalizer.band14kSlider"
        static let band16kSlider = "equalizer.band16kSlider"
        
        /// Get band slider identifier by index (0-9)
        static func bandSlider(_ index: Int) -> String {
            return "equalizer.bandSlider.\(index)"
        }
        
        // Graph
        static let eqGraph = "equalizer.eqGraph"
    }
    
    // MARK: - Plex Browser Window
    
    enum PlexBrowser {
        static let window = "plexBrowserWindow"
        
        // Window controls
        static let closeButton = "plexBrowser.closeButton"
        static let shadeButton = "plexBrowser.shadeButton"
        
        // Source selector
        static let sourceButton = "plexBrowser.sourceButton"
        
        // Mode tabs
        static let artistsTab = "plexBrowser.artistsTab"
        static let albumsTab = "plexBrowser.albumsTab"
        static let tracksTab = "plexBrowser.tracksTab"
        static let moviesTab = "plexBrowser.moviesTab"
        static let showsTab = "plexBrowser.showsTab"
        static let searchTab = "plexBrowser.searchTab"
        
        // Content
        static let contentList = "plexBrowser.contentList"
        static let itemCell = "plexBrowser.itemCell"  // Append index
        static let scrollbar = "plexBrowser.scrollbar"
        
        // Search
        static let searchField = "plexBrowser.searchField"
        
        // Bottom bar
        static let sortButton = "plexBrowser.sortButton"
        static let playButton = "plexBrowser.playButton"
        static let queueButton = "plexBrowser.queueButton"
        
        // Loading/Error
        static let loadingIndicator = "plexBrowser.loadingIndicator"
        static let errorMessage = "plexBrowser.errorMessage"
    }
    
    // MARK: - Visualization Window
    
    enum Visualization {
        static let window = "visualizationWindow"
        
        // Window controls
        static let closeButton = "visualization.closeButton"
        static let shadeButton = "visualization.shadeButton"
        
        // Content
        static let glView = "visualization.glView"
        
        // Preset info (for context menu)
        static let presetName = "visualization.presetName"
    }
    
    // MARK: - Video Player Window
    
    enum VideoPlayer {
        static let window = "videoPlayerWindow"
        
        // Controls
        static let playPauseButton = "videoPlayer.playPauseButton"
        static let seekSlider = "videoPlayer.seekSlider"
        static let volumeSlider = "videoPlayer.volumeSlider"
        static let fullscreenButton = "videoPlayer.fullscreenButton"
        
        // Display
        static let timeDisplay = "videoPlayer.timeDisplay"
        static let videoView = "videoPlayer.videoView"
    }
    
    // MARK: - Context Menu
    
    enum ContextMenu {
        static let menu = "contextMenu"
        static let playItem = "contextMenu.play"
        static let pauseItem = "contextMenu.pause"
        static let stopItem = "contextMenu.stop"
        static let previousItem = "contextMenu.previous"
        static let nextItem = "contextMenu.next"
        static let openFileItem = "contextMenu.openFile"
        static let openURLItem = "contextMenu.openURL"
        static let playlistItem = "contextMenu.playlist"
        static let equalizerItem = "contextMenu.equalizer"
        static let visualizationItem = "contextMenu.visualization"
        static let plexBrowserItem = "contextMenu.plexBrowser"
        static let skinItem = "contextMenu.skin"
        static let aboutItem = "contextMenu.about"
        static let quitItem = "contextMenu.quit"
    }
    
    // MARK: - Dialogs
    
    enum Dialogs {
        static let openFilePanel = "dialog.openFilePanel"
        static let saveFilePanel = "dialog.saveFilePanel"
        static let presetMenu = "dialog.presetMenu"
        static let aboutWindow = "dialog.aboutWindow"
    }
}
