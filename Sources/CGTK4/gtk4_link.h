// Umbrella header for GTK4 Swift import.
// On Linux these headers are provided by the gtk4 dev packages.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <gtk/gtk.h>
#include <gdk/gdk.h>
#include <glib.h>
#include <gio/gio.h>

static GtkApplication *_np_app = NULL;

static void _np_noop_activate(GtkApplication *app, gpointer data) {
    (void)app; (void)data;
}

static void _np_startup_cb(GApplication *app, gpointer data) {
    (void)app; (void)data;
}

static inline void np_linux_ui_init(void) {
    // G_APPLICATION_NON_UNIQUE disables D-Bus instance arbitration so this
    // process is always treated as the primary instance. That guarantees the
    // "startup" signal fires synchronously inside g_application_register(),
    // which triggers gtk_application_startup(): gtk_init() + display open +
    // CSS style-provider registration. Without this, bare gtk_init() alone
    // does not install the default CSS providers, causing a SIGSEGV in
    // gtk_css_value_initial_compute during the first gtk_window_new() call.
    _np_app = gtk_application_new("org.nullplayer.NullPlayerLinux",
                                  G_APPLICATION_NON_UNIQUE);
    g_signal_connect(_np_app, "startup", G_CALLBACK(_np_startup_cb), NULL);
    g_signal_connect(_np_app, "activate", G_CALLBACK(_np_noop_activate), NULL);
    GError *err = NULL;
    if (!g_application_register(G_APPLICATION(_np_app), NULL, &err) && err) {
        g_printerr("np_linux_ui_init: GtkApplication registration failed: %s\n",
                   err->message);
        g_error_free(err);
    }
}

static inline void *np_linux_ui_make_window(const char *title, int width, int height) {
    GtkWidget *window = gtk_window_new();
    gtk_window_set_title(GTK_WINDOW(window), title);
    gtk_window_set_default_size(GTK_WINDOW(window), width, height);
    // Associate with the application so GTK tracks this window's lifetime
    // and the CSS / style system has a valid application context.
    if (_np_app) {
        gtk_window_set_application(GTK_WINDOW(window), _np_app);
    }
    return window;
}

static inline void np_linux_ui_window_set_child(void *window, void *child) {
    gtk_window_set_child(GTK_WINDOW(window), GTK_WIDGET(child));
}

static inline void np_linux_ui_window_present(void *window) {
    gtk_window_present(GTK_WINDOW(window));
}

static inline void np_linux_ui_window_set_title(void *window, const char *title) {
    gtk_window_set_title(GTK_WINDOW(window), title);
}

static inline void np_linux_ui_window_hide(void *window) {
    gtk_widget_set_visible(GTK_WIDGET(window), FALSE);
}

static inline gboolean np_linux_ui_window_is_visible(void *window) {
    return gtk_widget_get_visible(GTK_WIDGET(window));
}

static inline void np_linux_ui_window_get_default_size(void *window, int *width, int *height) {
    gtk_window_get_default_size(GTK_WINDOW(window), width, height);
}

static inline void *np_linux_ui_make_library_playlist_panel(void) {
    GtkWidget *container = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_widget_set_margin_top(container, 12);
    gtk_widget_set_margin_bottom(container, 12);
    gtk_widget_set_margin_start(container, 12);
    gtk_widget_set_margin_end(container, 12);

    GtkWidget *heading = gtk_label_new("Library / Playlist prototype");
    gtk_widget_set_halign(heading, GTK_ALIGN_START);
    gtk_box_append(GTK_BOX(container), heading);

    GtkWidget *scroller = gtk_scrolled_window_new();
    gtk_widget_set_hexpand(scroller, TRUE);
    gtk_widget_set_vexpand(scroller, TRUE);

    GtkWidget *list = gtk_list_box_new();
    gtk_list_box_set_selection_mode(GTK_LIST_BOX(list), GTK_SELECTION_SINGLE);

    const char *rows[] = {
        "Now Playing Queue",
        "Artist: Boards of Canada",
        "Album: Music Has the Right to Children",
        "Track: Roygbiv",
        "Track: Olson",
        "Track: Aquarius",
        "Search: ambient"
    };
    const size_t rowCount = sizeof(rows) / sizeof(rows[0]);

    for (size_t i = 0; i < rowCount; ++i) {
        GtkWidget *row = gtk_list_box_row_new();
        GtkWidget *label = gtk_label_new(rows[i]);
        gtk_widget_set_halign(label, GTK_ALIGN_START);
        gtk_widget_set_margin_top(label, 6);
        gtk_widget_set_margin_bottom(label, 6);
        gtk_widget_set_margin_start(label, 8);
        gtk_widget_set_margin_end(label, 8);
        gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(row), label);
        gtk_list_box_append(GTK_LIST_BOX(list), row);
    }

    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroller), list);
    gtk_box_append(GTK_BOX(container), scroller);
    return container;
}

static inline void *np_linux_ui_make_secondary_panel(void) {
    GtkWidget *container = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_widget_set_margin_top(container, 16);
    gtk_widget_set_margin_bottom(container, 16);
    gtk_widget_set_margin_start(container, 16);
    gtk_widget_set_margin_end(container, 16);

    GtkWidget *title = gtk_label_new("Secondary window");
    gtk_widget_set_halign(title, GTK_ALIGN_START);
    gtk_box_append(GTK_BOX(container), title);

    GtkWidget *body = gtk_label_new("Placeholder for EQ / spectrum / waveform surfaces.");
    gtk_widget_set_halign(body, GTK_ALIGN_START);
    gtk_box_append(GTK_BOX(container), body);
    return container;
}

static inline void *np_linux_ui_make_placeholder_panel(const char *headingText, const char *bodyText) {
    GtkWidget *container = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
    gtk_widget_set_margin_top(container, 16);
    gtk_widget_set_margin_bottom(container, 16);
    gtk_widget_set_margin_start(container, 16);
    gtk_widget_set_margin_end(container, 16);

    GtkWidget *heading = gtk_label_new(headingText);
    gtk_widget_set_halign(heading, GTK_ALIGN_START);
    gtk_widget_add_css_class(heading, "heading");
    gtk_box_append(GTK_BOX(container), heading);

    GtkWidget *body = gtk_label_new(bodyText);
    gtk_widget_set_halign(body, GTK_ALIGN_START);
    gtk_label_set_wrap(GTK_LABEL(body), TRUE);
    gtk_box_append(GTK_BOX(container), body);

    return container;
}

// MARK: - Main Window Panel

typedef void (*np_linux_ui_main_action_cb)(int32_t action, void *user_data);
typedef void (*np_linux_ui_main_toggle_cb)(int32_t toggle_id, int32_t enabled, void *user_data);
typedef void (*np_linux_ui_main_value_cb)(double value, void *user_data);
typedef void (*np_linux_ui_main_drop_cb)(const char *payload, void *user_data);

enum {
    NP_LINUX_UI_MAIN_ACTION_PREVIOUS = 1,
    NP_LINUX_UI_MAIN_ACTION_PLAY = 2,
    NP_LINUX_UI_MAIN_ACTION_PAUSE = 3,
    NP_LINUX_UI_MAIN_ACTION_STOP = 4,
    NP_LINUX_UI_MAIN_ACTION_NEXT = 5,
    NP_LINUX_UI_MAIN_ACTION_OPEN_FILES = 6,
    NP_LINUX_UI_MAIN_ACTION_OPEN_FOLDER = 7,
    NP_LINUX_UI_MAIN_ACTION_CYCLE_OUTPUT = 8,
    NP_LINUX_UI_MAIN_ACTION_TOGGLE_PLAY_PAUSE = 9,
    NP_LINUX_UI_MAIN_ACTION_SEEK_BACKWARD = 10,
    NP_LINUX_UI_MAIN_ACTION_SEEK_FORWARD = 11
};

enum {
    NP_LINUX_UI_MAIN_TOGGLE_SHUFFLE = 1,
    NP_LINUX_UI_MAIN_TOGGLE_REPEAT = 2,
    NP_LINUX_UI_MAIN_TOGGLE_EQUALIZER = 3,
    NP_LINUX_UI_MAIN_TOGGLE_PLAYLIST = 4,
    NP_LINUX_UI_MAIN_TOGGLE_LIBRARY = 5,
    NP_LINUX_UI_MAIN_TOGGLE_SPECTRUM = 6,
    NP_LINUX_UI_MAIN_TOGGLE_WAVEFORM = 7,
    NP_LINUX_UI_MAIN_TOGGLE_PROJECTM = 8
};

typedef struct {
    GtkWidget *root;
    GtkWidget *track_label;
    GtkWidget *status_label;
    GtkWidget *time_label;
    GtkWidget *spectrum_label;
    GtkWidget *seek_scale;
    GtkWidget *volume_scale;
    GtkWidget *output_button;
    GtkWidget *shuffle_toggle;
    GtkWidget *repeat_toggle;
    GtkWidget *eq_toggle;
    GtkWidget *playlist_toggle;
    GtkWidget *library_toggle;
    GtkWidget *spectrum_toggle;
    GtkWidget *waveform_toggle;
    GtkWidget *projectm_toggle;
    GtkWidget *context_popover;
    gboolean suppress_seek_callback;
    gboolean suppress_volume_callback;
    gboolean suppress_toggle_callback;
    np_linux_ui_main_action_cb action_cb;
    np_linux_ui_main_toggle_cb toggle_cb;
    np_linux_ui_main_value_cb seek_cb;
    np_linux_ui_main_value_cb volume_cb;
    np_linux_ui_main_drop_cb drop_cb;
    void *user_data;
} NPLinuxMainPanel;

static inline void np_linux_ui_main_button_clicked(GtkButton *clickedButton, gpointer data) {
    NPLinuxMainPanel *state = (NPLinuxMainPanel *)data;
    if (state == NULL || state->action_cb == NULL) {
        return;
    }
    gpointer actionPtr = g_object_get_data(G_OBJECT(clickedButton), "np-action-id");
    state->action_cb((int32_t)GPOINTER_TO_INT(actionPtr), state->user_data);
}

static inline void np_linux_ui_main_toggle_toggled(GtkToggleButton *toggledButton, gpointer data) {
    NPLinuxMainPanel *state = (NPLinuxMainPanel *)data;
    if (state == NULL || state->toggle_cb == NULL || state->suppress_toggle_callback) {
        return;
    }
    gpointer togglePtr = g_object_get_data(G_OBJECT(toggledButton), "np-toggle-id");
    int32_t enabled = gtk_toggle_button_get_active(toggledButton) ? 1 : 0;
    state->toggle_cb((int32_t)GPOINTER_TO_INT(togglePtr), enabled, state->user_data);
}

static inline void np_linux_ui_main_seek_value_changed(GtkRange *range, gpointer data) {
    NPLinuxMainPanel *state = (NPLinuxMainPanel *)data;
    if (state == NULL || state->seek_cb == NULL || state->suppress_seek_callback) {
        return;
    }
    state->seek_cb(gtk_range_get_value(range), state->user_data);
}

static inline void np_linux_ui_main_volume_value_changed(GtkRange *range, gpointer data) {
    NPLinuxMainPanel *state = (NPLinuxMainPanel *)data;
    if (state == NULL || state->volume_cb == NULL || state->suppress_volume_callback) {
        return;
    }
    state->volume_cb(gtk_range_get_value(range), state->user_data);
}

static inline void np_linux_ui_main_show_context_menu(NPLinuxMainPanel *panel, double x, double y);

static inline void np_linux_ui_main_secondary_pressed(
    GtkGestureClick *gesture,
    gint n_press,
    double x,
    double y,
    gpointer data
) {
    (void)gesture;
    if (n_press != 1) {
        return;
    }
    NPLinuxMainPanel *panel = (NPLinuxMainPanel *)data;
    if (panel == NULL) {
        return;
    }
    np_linux_ui_main_show_context_menu(panel, x, y);
}

static inline gboolean np_linux_ui_main_drop_received(
    GtkDropTarget *target,
    const GValue *value,
    double x,
    double y,
    gpointer data
) {
    (void)target;
    (void)x;
    (void)y;

    NPLinuxMainPanel *state = (NPLinuxMainPanel *)data;
    if (state == NULL || state->drop_cb == NULL) {
        return FALSE;
    }

    if (G_VALUE_HOLDS_STRING(value)) {
        const char *payload = g_value_get_string(value);
        if (payload != NULL) {
            state->drop_cb(payload, state->user_data);
            return TRUE;
        }
    }

    return FALSE;
}

static inline GtkWidget *np_linux_ui_main_make_action_button(NPLinuxMainPanel *panel, const char *title, int32_t action_id) {
    GtkWidget *button = gtk_button_new_with_label(title);
    g_object_set_data(G_OBJECT(button), "np-action-id", GINT_TO_POINTER((gint)action_id));
    g_signal_connect(button, "clicked", G_CALLBACK(np_linux_ui_main_button_clicked), panel);
    return button;
}

static inline GtkWidget *np_linux_ui_main_make_toggle(NPLinuxMainPanel *panel, const char *title, int32_t toggle_id) {
    GtkWidget *toggle = gtk_check_button_new_with_label(title);
    g_object_set_data(G_OBJECT(toggle), "np-toggle-id", GINT_TO_POINTER((gint)toggle_id));
    g_signal_connect(toggle, "toggled", G_CALLBACK(np_linux_ui_main_toggle_toggled), panel);
    return toggle;
}

static inline gboolean np_linux_ui_main_key_pressed(
    GtkEventControllerKey *controller,
    guint keyval,
    guint keycode,
    GdkModifierType state,
    gpointer user_data
) {
    (void)controller;
    (void)keycode;

    NPLinuxMainPanel *panel = (NPLinuxMainPanel *)user_data;
    if (panel == NULL || panel->action_cb == NULL) {
        return FALSE;
    }

    gboolean controlPressed = (state & GDK_CONTROL_MASK) != 0;

    if (keyval == GDK_KEY_space) {
        panel->action_cb(NP_LINUX_UI_MAIN_ACTION_TOGGLE_PLAY_PAUSE, panel->user_data);
        return TRUE;
    }

    if (keyval == GDK_KEY_Left) {
        panel->action_cb(NP_LINUX_UI_MAIN_ACTION_SEEK_BACKWARD, panel->user_data);
        return TRUE;
    }

    if (keyval == GDK_KEY_Right) {
        panel->action_cb(NP_LINUX_UI_MAIN_ACTION_SEEK_FORWARD, panel->user_data);
        return TRUE;
    }

    if (controlPressed) {
        switch (keyval) {
            case GDK_KEY_o:
            case GDK_KEY_O:
                panel->action_cb(NP_LINUX_UI_MAIN_ACTION_OPEN_FILES, panel->user_data);
                return TRUE;
            case GDK_KEY_p:
            case GDK_KEY_P:
                panel->toggle_cb(NP_LINUX_UI_MAIN_TOGGLE_PLAYLIST, 1, panel->user_data);
                return TRUE;
            case GDK_KEY_e:
            case GDK_KEY_E:
                panel->toggle_cb(NP_LINUX_UI_MAIN_TOGGLE_EQUALIZER, 1, panel->user_data);
                return TRUE;
            case GDK_KEY_b:
            case GDK_KEY_B:
                panel->toggle_cb(NP_LINUX_UI_MAIN_TOGGLE_LIBRARY, 1, panel->user_data);
                return TRUE;
            case GDK_KEY_s:
            case GDK_KEY_S:
                panel->toggle_cb(NP_LINUX_UI_MAIN_TOGGLE_SPECTRUM, 1, panel->user_data);
                return TRUE;
            case GDK_KEY_w:
            case GDK_KEY_W:
                panel->toggle_cb(NP_LINUX_UI_MAIN_TOGGLE_WAVEFORM, 1, panel->user_data);
                return TRUE;
            case GDK_KEY_m:
            case GDK_KEY_M:
                panel->toggle_cb(NP_LINUX_UI_MAIN_TOGGLE_PROJECTM, 1, panel->user_data);
                return TRUE;
            default:
                break;
        }
    }

    return FALSE;
}

static inline void *np_linux_ui_make_main_panel(
    void *user_data,
    np_linux_ui_main_action_cb action_cb,
    np_linux_ui_main_toggle_cb toggle_cb,
    np_linux_ui_main_value_cb seek_cb,
    np_linux_ui_main_value_cb volume_cb,
    np_linux_ui_main_drop_cb drop_cb
) {
    NPLinuxMainPanel *panel = (NPLinuxMainPanel *)calloc(1, sizeof(NPLinuxMainPanel));
    panel->action_cb = action_cb;
    panel->toggle_cb = toggle_cb;
    panel->seek_cb = seek_cb;
    panel->volume_cb = volume_cb;
    panel->drop_cb = drop_cb;
    panel->user_data = user_data;

    GtkWidget *root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
    panel->root = root;
    gtk_widget_set_margin_top(root, 12);
    gtk_widget_set_margin_bottom(root, 12);
    gtk_widget_set_margin_start(root, 12);
    gtk_widget_set_margin_end(root, 12);

    panel->track_label = gtk_label_new("No track loaded");
    gtk_widget_set_halign(panel->track_label, GTK_ALIGN_START);
    gtk_widget_set_hexpand(panel->track_label, TRUE);
    gtk_box_append(GTK_BOX(root), panel->track_label);

    panel->status_label = gtk_label_new("Stopped");
    gtk_widget_set_halign(panel->status_label, GTK_ALIGN_START);
    gtk_box_append(GTK_BOX(root), panel->status_label);

    panel->time_label = gtk_label_new("0:00 / 0:00");
    gtk_widget_set_halign(panel->time_label, GTK_ALIGN_START);
    gtk_box_append(GTK_BOX(root), panel->time_label);

    panel->seek_scale = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 0.0, 100.0, 1.0);
    gtk_scale_set_draw_value(GTK_SCALE(panel->seek_scale), FALSE);
    gtk_widget_set_hexpand(panel->seek_scale, TRUE);
    g_signal_connect(panel->seek_scale, "value-changed", G_CALLBACK(np_linux_ui_main_seek_value_changed), panel);
    gtk_box_append(GTK_BOX(root), panel->seek_scale);

    GtkWidget *transportRow = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_box_append(GTK_BOX(transportRow), np_linux_ui_main_make_action_button(panel, "Prev", NP_LINUX_UI_MAIN_ACTION_PREVIOUS));
    gtk_box_append(GTK_BOX(transportRow), np_linux_ui_main_make_action_button(panel, "Play", NP_LINUX_UI_MAIN_ACTION_PLAY));
    gtk_box_append(GTK_BOX(transportRow), np_linux_ui_main_make_action_button(panel, "Pause", NP_LINUX_UI_MAIN_ACTION_PAUSE));
    gtk_box_append(GTK_BOX(transportRow), np_linux_ui_main_make_action_button(panel, "Stop", NP_LINUX_UI_MAIN_ACTION_STOP));
    gtk_box_append(GTK_BOX(transportRow), np_linux_ui_main_make_action_button(panel, "Next", NP_LINUX_UI_MAIN_ACTION_NEXT));
    gtk_box_append(GTK_BOX(transportRow), np_linux_ui_main_make_action_button(panel, "Open Files", NP_LINUX_UI_MAIN_ACTION_OPEN_FILES));
    gtk_box_append(GTK_BOX(transportRow), np_linux_ui_main_make_action_button(panel, "Open Folder", NP_LINUX_UI_MAIN_ACTION_OPEN_FOLDER));
    gtk_box_append(GTK_BOX(root), transportRow);

    GtkWidget *toggleRow = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    panel->shuffle_toggle = np_linux_ui_main_make_toggle(panel, "Shuffle", NP_LINUX_UI_MAIN_TOGGLE_SHUFFLE);
    panel->repeat_toggle = np_linux_ui_main_make_toggle(panel, "Repeat", NP_LINUX_UI_MAIN_TOGGLE_REPEAT);
    gtk_box_append(GTK_BOX(toggleRow), panel->shuffle_toggle);
    gtk_box_append(GTK_BOX(toggleRow), panel->repeat_toggle);
    gtk_box_append(GTK_BOX(root), toggleRow);

    GtkWidget *windowsRow = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    panel->eq_toggle = np_linux_ui_main_make_toggle(panel, "EQ", NP_LINUX_UI_MAIN_TOGGLE_EQUALIZER);
    panel->playlist_toggle = np_linux_ui_main_make_toggle(panel, "Playlist", NP_LINUX_UI_MAIN_TOGGLE_PLAYLIST);
    panel->library_toggle = np_linux_ui_main_make_toggle(panel, "Library", NP_LINUX_UI_MAIN_TOGGLE_LIBRARY);
    panel->spectrum_toggle = np_linux_ui_main_make_toggle(panel, "Spectrum", NP_LINUX_UI_MAIN_TOGGLE_SPECTRUM);
    panel->waveform_toggle = np_linux_ui_main_make_toggle(panel, "Waveform", NP_LINUX_UI_MAIN_TOGGLE_WAVEFORM);
    panel->projectm_toggle = np_linux_ui_main_make_toggle(panel, "projectM", NP_LINUX_UI_MAIN_TOGGLE_PROJECTM);
    gtk_box_append(GTK_BOX(windowsRow), panel->eq_toggle);
    gtk_box_append(GTK_BOX(windowsRow), panel->playlist_toggle);
    gtk_box_append(GTK_BOX(windowsRow), panel->library_toggle);
    gtk_box_append(GTK_BOX(windowsRow), panel->spectrum_toggle);
    gtk_box_append(GTK_BOX(windowsRow), panel->waveform_toggle);
    gtk_box_append(GTK_BOX(windowsRow), panel->projectm_toggle);
    gtk_box_append(GTK_BOX(root), windowsRow);

    panel->volume_scale = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 0.0, 1.0, 0.01);
    gtk_scale_set_draw_value(GTK_SCALE(panel->volume_scale), FALSE);
    gtk_range_set_value(GTK_RANGE(panel->volume_scale), 0.2);
    g_signal_connect(panel->volume_scale, "value-changed", G_CALLBACK(np_linux_ui_main_volume_value_changed), panel);
    gtk_box_append(GTK_BOX(root), panel->volume_scale);

    GtkWidget *footer = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    panel->output_button = np_linux_ui_main_make_action_button(panel, "Output: Default", NP_LINUX_UI_MAIN_ACTION_CYCLE_OUTPUT);
    gtk_box_append(GTK_BOX(footer), panel->output_button);

    GtkWidget *appearance = gtk_label_new("Appearance button deferred on Linux (Phase 3)");
    gtk_widget_set_halign(appearance, GTK_ALIGN_START);
    gtk_box_append(GTK_BOX(footer), appearance);
    gtk_box_append(GTK_BOX(root), footer);

    panel->spectrum_label = gtk_label_new("Mini visualization: waiting for spectrum data");
    gtk_widget_set_halign(panel->spectrum_label, GTK_ALIGN_START);
    gtk_box_append(GTK_BOX(root), panel->spectrum_label);

    GtkEventController *keyController = gtk_event_controller_key_new();
    g_signal_connect(keyController, "key-pressed", G_CALLBACK(np_linux_ui_main_key_pressed), panel);
    gtk_widget_add_controller(root, keyController);

    GtkDropTarget *dropTarget = gtk_drop_target_new(G_TYPE_STRING, GDK_ACTION_COPY);
    g_signal_connect(dropTarget, "drop", G_CALLBACK(np_linux_ui_main_drop_received), panel);
    gtk_widget_add_controller(root, GTK_EVENT_CONTROLLER(dropTarget));

    GtkGesture *secondaryClick = gtk_gesture_click_new();
    gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(secondaryClick), GDK_BUTTON_SECONDARY);
    g_signal_connect(secondaryClick, "pressed", G_CALLBACK(np_linux_ui_main_secondary_pressed), panel);
    gtk_widget_add_controller(root, GTK_EVENT_CONTROLLER(secondaryClick));

    return panel;
}

static inline void *np_linux_ui_main_panel_widget(void *main_panel) {
    NPLinuxMainPanel *panel = (NPLinuxMainPanel *)main_panel;
    if (panel == NULL) {
        return NULL;
    }
    return panel->root;
}

static inline GtkWidget *np_linux_ui_main_toggle_widget(NPLinuxMainPanel *panel, int32_t toggle_id) {
    switch (toggle_id) {
        case NP_LINUX_UI_MAIN_TOGGLE_SHUFFLE: return panel->shuffle_toggle;
        case NP_LINUX_UI_MAIN_TOGGLE_REPEAT: return panel->repeat_toggle;
        case NP_LINUX_UI_MAIN_TOGGLE_EQUALIZER: return panel->eq_toggle;
        case NP_LINUX_UI_MAIN_TOGGLE_PLAYLIST: return panel->playlist_toggle;
        case NP_LINUX_UI_MAIN_TOGGLE_LIBRARY: return panel->library_toggle;
        case NP_LINUX_UI_MAIN_TOGGLE_SPECTRUM: return panel->spectrum_toggle;
        case NP_LINUX_UI_MAIN_TOGGLE_WAVEFORM: return panel->waveform_toggle;
        case NP_LINUX_UI_MAIN_TOGGLE_PROJECTM: return panel->projectm_toggle;
        default: return NULL;
    }
}

static inline void np_linux_ui_main_panel_set_track_title(void *main_panel, const char *text) {
    NPLinuxMainPanel *panel = (NPLinuxMainPanel *)main_panel;
    if (panel == NULL || panel->track_label == NULL) {
        return;
    }
    gtk_label_set_text(GTK_LABEL(panel->track_label), text);
}

static inline void np_linux_ui_main_panel_set_status(void *main_panel, const char *text) {
    NPLinuxMainPanel *panel = (NPLinuxMainPanel *)main_panel;
    if (panel == NULL || panel->status_label == NULL) {
        return;
    }
    gtk_label_set_text(GTK_LABEL(panel->status_label), text);
}

static inline void np_linux_ui_main_panel_set_time(void *main_panel, double current, double duration) {
    NPLinuxMainPanel *panel = (NPLinuxMainPanel *)main_panel;
    if (panel == NULL || panel->time_label == NULL) {
        return;
    }

    int currentSeconds = (int)(current < 0 ? 0 : current);
    int durationSeconds = (int)(duration < 0 ? 0 : duration);

    char buffer[64];
    snprintf(
        buffer,
        sizeof(buffer),
        "%d:%02d / %d:%02d",
        currentSeconds / 60,
        currentSeconds % 60,
        durationSeconds / 60,
        durationSeconds % 60
    );
    gtk_label_set_text(GTK_LABEL(panel->time_label), buffer);
}

static inline void np_linux_ui_main_panel_set_seek_range(void *main_panel, double max_value) {
    NPLinuxMainPanel *panel = (NPLinuxMainPanel *)main_panel;
    if (panel == NULL || panel->seek_scale == NULL) {
        return;
    }
    double upper = max_value > 0 ? max_value : 1.0;
    gtk_range_set_range(GTK_RANGE(panel->seek_scale), 0.0, upper);
}

static inline void np_linux_ui_main_panel_set_seek_value(void *main_panel, double value) {
    NPLinuxMainPanel *panel = (NPLinuxMainPanel *)main_panel;
    if (panel == NULL || panel->seek_scale == NULL) {
        return;
    }
    panel->suppress_seek_callback = TRUE;
    gtk_range_set_value(GTK_RANGE(panel->seek_scale), value);
    panel->suppress_seek_callback = FALSE;
}

static inline void np_linux_ui_main_panel_set_volume_value(void *main_panel, double value) {
    NPLinuxMainPanel *panel = (NPLinuxMainPanel *)main_panel;
    if (panel == NULL || panel->volume_scale == NULL) {
        return;
    }
    panel->suppress_volume_callback = TRUE;
    gtk_range_set_value(GTK_RANGE(panel->volume_scale), value);
    panel->suppress_volume_callback = FALSE;
}

static inline void np_linux_ui_main_panel_set_toggle_state(void *main_panel, int32_t toggle_id, int32_t enabled) {
    NPLinuxMainPanel *panel = (NPLinuxMainPanel *)main_panel;
    if (panel == NULL) {
        return;
    }

    GtkWidget *toggle = np_linux_ui_main_toggle_widget(panel, toggle_id);
    if (toggle == NULL) {
        return;
    }

    panel->suppress_toggle_callback = TRUE;
    gtk_check_button_set_active(GTK_CHECK_BUTTON(toggle), enabled != 0);
    panel->suppress_toggle_callback = FALSE;
}

static inline void np_linux_ui_main_panel_set_output_label(void *main_panel, const char *text) {
    NPLinuxMainPanel *panel = (NPLinuxMainPanel *)main_panel;
    if (panel == NULL || panel->output_button == NULL) {
        return;
    }
    gtk_button_set_label(GTK_BUTTON(panel->output_button), text);
}

static inline void np_linux_ui_main_panel_set_spectrum_summary(void *main_panel, const char *text) {
    NPLinuxMainPanel *panel = (NPLinuxMainPanel *)main_panel;
    if (panel == NULL || panel->spectrum_label == NULL) {
        return;
    }
    gtk_label_set_text(GTK_LABEL(panel->spectrum_label), text);
}

static inline void np_linux_ui_main_show_context_menu(NPLinuxMainPanel *panel, double x, double y) {
    if (panel == NULL || panel->root == NULL) {
        return;
    }

    if (panel->context_popover == NULL) {
        GtkWidget *popover = gtk_popover_new();
        gtk_widget_set_parent(popover, panel->root);

        GtkWidget *menuBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
        gtk_widget_set_margin_top(menuBox, 8);
        gtk_widget_set_margin_bottom(menuBox, 8);
        gtk_widget_set_margin_start(menuBox, 8);
        gtk_widget_set_margin_end(menuBox, 8);

        gtk_box_append(GTK_BOX(menuBox), np_linux_ui_main_make_action_button(panel, "Play/Pause", NP_LINUX_UI_MAIN_ACTION_TOGGLE_PLAY_PAUSE));
        gtk_box_append(GTK_BOX(menuBox), np_linux_ui_main_make_action_button(panel, "Stop", NP_LINUX_UI_MAIN_ACTION_STOP));
        gtk_box_append(GTK_BOX(menuBox), np_linux_ui_main_make_action_button(panel, "Previous", NP_LINUX_UI_MAIN_ACTION_PREVIOUS));
        gtk_box_append(GTK_BOX(menuBox), np_linux_ui_main_make_action_button(panel, "Next", NP_LINUX_UI_MAIN_ACTION_NEXT));
        gtk_box_append(GTK_BOX(menuBox), np_linux_ui_main_make_action_button(panel, "Open Files", NP_LINUX_UI_MAIN_ACTION_OPEN_FILES));
        gtk_box_append(GTK_BOX(menuBox), np_linux_ui_main_make_action_button(panel, "Open Folder", NP_LINUX_UI_MAIN_ACTION_OPEN_FOLDER));

        gtk_popover_set_child(GTK_POPOVER(popover), menuBox);
        panel->context_popover = popover;
    }

    GdkRectangle targetRect = { (int)x, (int)y, 1, 1 };
    gtk_popover_set_pointing_to(GTK_POPOVER(panel->context_popover), &targetRect);
    gtk_popover_popup(GTK_POPOVER(panel->context_popover));
}

// MARK: - Playlist Window Panel

typedef void (*np_linux_ui_playlist_action_cb)(int32_t action, int32_t index, void *user_data);
typedef void (*np_linux_ui_playlist_drop_cb)(const char *payload, void *user_data);

enum {
    NP_LINUX_UI_PLAYLIST_ACTION_PLAY_SELECTED = 1,
    NP_LINUX_UI_PLAYLIST_ACTION_REMOVE_SELECTED = 2,
    NP_LINUX_UI_PLAYLIST_ACTION_CLEAR = 3,
    NP_LINUX_UI_PLAYLIST_ACTION_SHUFFLE = 4,
    NP_LINUX_UI_PLAYLIST_ACTION_REVERSE = 5,
    NP_LINUX_UI_PLAYLIST_ACTION_SORT_TITLE = 6,
    NP_LINUX_UI_PLAYLIST_ACTION_SORT_ARTIST = 7,
    NP_LINUX_UI_PLAYLIST_ACTION_SORT_ALBUM = 8,
    NP_LINUX_UI_PLAYLIST_ACTION_RANDOMIZE = 9,
    NP_LINUX_UI_PLAYLIST_ACTION_ADD_FILES = 10,
    NP_LINUX_UI_PLAYLIST_ACTION_ADD_DIRECTORY = 11,
    NP_LINUX_UI_PLAYLIST_ACTION_ADD_URL = 12,
    NP_LINUX_UI_PLAYLIST_ACTION_CROP_SELECTION = 13,
    NP_LINUX_UI_PLAYLIST_ACTION_REMOVE_DEAD_FILES = 14,
    NP_LINUX_UI_PLAYLIST_ACTION_SORT_FILENAME = 15,
    NP_LINUX_UI_PLAYLIST_ACTION_SORT_PATH = 16,
    NP_LINUX_UI_PLAYLIST_ACTION_FILE_INFO = 17,
    NP_LINUX_UI_PLAYLIST_ACTION_SAVE_PLAYLIST = 18,
    NP_LINUX_UI_PLAYLIST_ACTION_LOAD_PLAYLIST = 19,
    NP_LINUX_UI_PLAYLIST_ACTION_NEW_PLAYLIST = 20
};

typedef struct {
    GtkWidget *root;
    GtkWidget *list;
    GtkWidget *empty_label;
    GtkWidget *context_popover;
    int32_t row_count;
    np_linux_ui_playlist_action_cb action_cb;
    np_linux_ui_playlist_drop_cb drop_cb;
    void *user_data;
} NPLinuxPlaylistPanel;

static inline int32_t np_linux_ui_playlist_selected_index(NPLinuxPlaylistPanel *panel) {
    if (panel == NULL || panel->list == NULL) {
        return -1;
    }

    GList *selectedRows = gtk_list_box_get_selected_rows(GTK_LIST_BOX(panel->list));
    if (selectedRows == NULL) {
        return -1;
    }

    GtkListBoxRow *selectedRow = GTK_LIST_BOX_ROW(selectedRows->data);
    gpointer indexData = g_object_get_data(G_OBJECT(selectedRow), "np-track-index");
    int32_t index = (int32_t)GPOINTER_TO_INT(indexData);
    g_list_free(selectedRows);
    return index;
}

static inline void np_linux_ui_playlist_button_clicked(GtkButton *clickedButton, gpointer data) {
    NPLinuxPlaylistPanel *state = (NPLinuxPlaylistPanel *)data;
    if (state == NULL || state->action_cb == NULL) {
        return;
    }

    gpointer actionPtr = g_object_get_data(G_OBJECT(clickedButton), "np-playlist-action-id");
    int32_t actionID = (int32_t)GPOINTER_TO_INT(actionPtr);
    int32_t selectedIndex = np_linux_ui_playlist_selected_index(state);
    state->action_cb(actionID, selectedIndex, state->user_data);
}

static inline void np_linux_ui_playlist_row_activated(GtkListBox *listBox, GtkListBoxRow *row, gpointer data) {
    (void)listBox;
    NPLinuxPlaylistPanel *state = (NPLinuxPlaylistPanel *)data;
    if (state == NULL || state->action_cb == NULL || row == NULL) {
        return;
    }
    gpointer indexData = g_object_get_data(G_OBJECT(row), "np-track-index");
    int32_t index = (int32_t)GPOINTER_TO_INT(indexData);
    state->action_cb(NP_LINUX_UI_PLAYLIST_ACTION_PLAY_SELECTED, index, state->user_data);
}

static inline gboolean np_linux_ui_playlist_drop_received(
    GtkDropTarget *target,
    const GValue *value,
    double x,
    double y,
    gpointer data
) {
    (void)target;
    (void)x;
    (void)y;

    NPLinuxPlaylistPanel *state = (NPLinuxPlaylistPanel *)data;
    if (state == NULL || state->drop_cb == NULL) {
        return FALSE;
    }

    if (G_VALUE_HOLDS_STRING(value)) {
        const char *payload = g_value_get_string(value);
        if (payload != NULL) {
            state->drop_cb(payload, state->user_data);
            return TRUE;
        }
    }

    return FALSE;
}

static inline void np_linux_ui_playlist_show_context_menu(NPLinuxPlaylistPanel *panel, double x, double y);

static inline void np_linux_ui_playlist_secondary_pressed(
    GtkGestureClick *gesture,
    gint n_press,
    double x,
    double y,
    gpointer data
) {
    (void)gesture;
    if (n_press != 1) {
        return;
    }
    NPLinuxPlaylistPanel *panel = (NPLinuxPlaylistPanel *)data;
    if (panel == NULL) {
        return;
    }
    np_linux_ui_playlist_show_context_menu(panel, x, y);
}

static inline GtkWidget *np_linux_ui_playlist_make_button(NPLinuxPlaylistPanel *panel, const char *title, int32_t action_id) {
    GtkWidget *button = gtk_button_new_with_label(title);
    g_object_set_data(G_OBJECT(button), "np-playlist-action-id", GINT_TO_POINTER((gint)action_id));
    g_signal_connect(button, "clicked", G_CALLBACK(np_linux_ui_playlist_button_clicked), panel);
    return button;
}

static inline void *np_linux_ui_make_playlist_panel(
    void *user_data,
    np_linux_ui_playlist_action_cb action_cb,
    np_linux_ui_playlist_drop_cb drop_cb
) {
    NPLinuxPlaylistPanel *panel = (NPLinuxPlaylistPanel *)calloc(1, sizeof(NPLinuxPlaylistPanel));
    panel->action_cb = action_cb;
    panel->drop_cb = drop_cb;
    panel->user_data = user_data;

    GtkWidget *root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    panel->root = root;
    gtk_widget_set_margin_top(root, 12);
    gtk_widget_set_margin_bottom(root, 12);
    gtk_widget_set_margin_start(root, 12);
    gtk_widget_set_margin_end(root, 12);

    GtkWidget *header = gtk_label_new("Playlist Queue");
    gtk_widget_set_halign(header, GTK_ALIGN_START);
    gtk_box_append(GTK_BOX(root), header);

    GtkWidget *scroller = gtk_scrolled_window_new();
    gtk_widget_set_hexpand(scroller, TRUE);
    gtk_widget_set_vexpand(scroller, TRUE);

    panel->list = gtk_list_box_new();
    gtk_list_box_set_selection_mode(GTK_LIST_BOX(panel->list), GTK_SELECTION_MULTIPLE);
    g_signal_connect(panel->list, "row-activated", G_CALLBACK(np_linux_ui_playlist_row_activated), panel);

    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroller), panel->list);
    gtk_box_append(GTK_BOX(root), scroller);

    panel->empty_label = gtk_label_new("Playlist is empty");
    gtk_widget_set_halign(panel->empty_label, GTK_ALIGN_START);
    gtk_box_append(GTK_BOX(root), panel->empty_label);

    GtkWidget *rowOne = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_box_append(GTK_BOX(rowOne), np_linux_ui_playlist_make_button(panel, "Add Files", NP_LINUX_UI_PLAYLIST_ACTION_ADD_FILES));
    gtk_box_append(GTK_BOX(rowOne), np_linux_ui_playlist_make_button(panel, "Add Folder", NP_LINUX_UI_PLAYLIST_ACTION_ADD_DIRECTORY));
    gtk_box_append(GTK_BOX(rowOne), np_linux_ui_playlist_make_button(panel, "Add URL", NP_LINUX_UI_PLAYLIST_ACTION_ADD_URL));
    gtk_box_append(GTK_BOX(rowOne), np_linux_ui_playlist_make_button(panel, "Play", NP_LINUX_UI_PLAYLIST_ACTION_PLAY_SELECTED));
    gtk_box_append(GTK_BOX(rowOne), np_linux_ui_playlist_make_button(panel, "Remove", NP_LINUX_UI_PLAYLIST_ACTION_REMOVE_SELECTED));
    gtk_box_append(GTK_BOX(rowOne), np_linux_ui_playlist_make_button(panel, "Crop", NP_LINUX_UI_PLAYLIST_ACTION_CROP_SELECTION));
    gtk_box_append(GTK_BOX(rowOne), np_linux_ui_playlist_make_button(panel, "Clear", NP_LINUX_UI_PLAYLIST_ACTION_CLEAR));
    gtk_box_append(GTK_BOX(root), rowOne);

    GtkWidget *rowTwo = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_box_append(GTK_BOX(rowTwo), np_linux_ui_playlist_make_button(panel, "Shuffle", NP_LINUX_UI_PLAYLIST_ACTION_SHUFFLE));
    gtk_box_append(GTK_BOX(rowTwo), np_linux_ui_playlist_make_button(panel, "Reverse", NP_LINUX_UI_PLAYLIST_ACTION_REVERSE));
    gtk_box_append(GTK_BOX(rowTwo), np_linux_ui_playlist_make_button(panel, "Randomize", NP_LINUX_UI_PLAYLIST_ACTION_RANDOMIZE));
    gtk_box_append(GTK_BOX(rowTwo), np_linux_ui_playlist_make_button(panel, "Sort Title", NP_LINUX_UI_PLAYLIST_ACTION_SORT_TITLE));
    gtk_box_append(GTK_BOX(rowTwo), np_linux_ui_playlist_make_button(panel, "Sort Artist", NP_LINUX_UI_PLAYLIST_ACTION_SORT_ARTIST));
    gtk_box_append(GTK_BOX(rowTwo), np_linux_ui_playlist_make_button(panel, "Sort Album", NP_LINUX_UI_PLAYLIST_ACTION_SORT_ALBUM));
    gtk_box_append(GTK_BOX(rowTwo), np_linux_ui_playlist_make_button(panel, "Sort File", NP_LINUX_UI_PLAYLIST_ACTION_SORT_FILENAME));
    gtk_box_append(GTK_BOX(rowTwo), np_linux_ui_playlist_make_button(panel, "Sort Path", NP_LINUX_UI_PLAYLIST_ACTION_SORT_PATH));
    gtk_box_append(GTK_BOX(root), rowTwo);

    GtkWidget *rowThree = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_box_append(GTK_BOX(rowThree), np_linux_ui_playlist_make_button(panel, "Remove Dead", NP_LINUX_UI_PLAYLIST_ACTION_REMOVE_DEAD_FILES));
    gtk_box_append(GTK_BOX(rowThree), np_linux_ui_playlist_make_button(panel, "Info", NP_LINUX_UI_PLAYLIST_ACTION_FILE_INFO));
    gtk_box_append(GTK_BOX(rowThree), np_linux_ui_playlist_make_button(panel, "New", NP_LINUX_UI_PLAYLIST_ACTION_NEW_PLAYLIST));
    gtk_box_append(GTK_BOX(rowThree), np_linux_ui_playlist_make_button(panel, "Save", NP_LINUX_UI_PLAYLIST_ACTION_SAVE_PLAYLIST));
    gtk_box_append(GTK_BOX(rowThree), np_linux_ui_playlist_make_button(panel, "Load", NP_LINUX_UI_PLAYLIST_ACTION_LOAD_PLAYLIST));
    gtk_box_append(GTK_BOX(root), rowThree);

    GtkDropTarget *dropTarget = gtk_drop_target_new(G_TYPE_STRING, GDK_ACTION_COPY);
    g_signal_connect(dropTarget, "drop", G_CALLBACK(np_linux_ui_playlist_drop_received), panel);
    gtk_widget_add_controller(root, GTK_EVENT_CONTROLLER(dropTarget));

    GtkGesture *secondaryClick = gtk_gesture_click_new();
    gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(secondaryClick), GDK_BUTTON_SECONDARY);
    g_signal_connect(secondaryClick, "pressed", G_CALLBACK(np_linux_ui_playlist_secondary_pressed), panel);
    gtk_widget_add_controller(root, GTK_EVENT_CONTROLLER(secondaryClick));

    return panel;
}

static inline void *np_linux_ui_playlist_panel_widget(void *playlist_panel) {
    NPLinuxPlaylistPanel *panel = (NPLinuxPlaylistPanel *)playlist_panel;
    if (panel == NULL) {
        return NULL;
    }
    return panel->root;
}

static inline void np_linux_ui_playlist_panel_begin_update(void *playlist_panel) {
    NPLinuxPlaylistPanel *panel = (NPLinuxPlaylistPanel *)playlist_panel;
    if (panel == NULL || panel->list == NULL) {
        return;
    }

    GtkWidget *child = gtk_widget_get_first_child(panel->list);
    while (child != NULL) {
        GtkWidget *next = gtk_widget_get_next_sibling(child);
        gtk_list_box_remove(GTK_LIST_BOX(panel->list), child);
        child = next;
    }

    panel->row_count = 0;
}

static inline void np_linux_ui_playlist_panel_append_track(void *playlist_panel, const char *title, int32_t is_current) {
    NPLinuxPlaylistPanel *panel = (NPLinuxPlaylistPanel *)playlist_panel;
    if (panel == NULL || panel->list == NULL) {
        return;
    }

    GtkWidget *row = gtk_list_box_row_new();
    GtkWidget *label = gtk_label_new(title);
    gtk_widget_set_halign(label, GTK_ALIGN_START);
    gtk_widget_set_margin_top(label, 4);
    gtk_widget_set_margin_bottom(label, 4);
    gtk_widget_set_margin_start(label, 8);
    gtk_widget_set_margin_end(label, 8);

    if (is_current != 0) {
        gtk_widget_add_css_class(label, "heading");
    }

    gtk_list_box_row_set_child(GTK_LIST_BOX_ROW(row), label);
    g_object_set_data(G_OBJECT(row), "np-track-index", GINT_TO_POINTER((gint)panel->row_count));
    gtk_list_box_append(GTK_LIST_BOX(panel->list), row);

    panel->row_count += 1;
}

static inline void np_linux_ui_playlist_panel_finish_update(void *playlist_panel, int32_t current_index) {
    NPLinuxPlaylistPanel *panel = (NPLinuxPlaylistPanel *)playlist_panel;
    if (panel == NULL || panel->list == NULL) {
        return;
    }

    gtk_widget_set_visible(panel->empty_label, panel->row_count == 0);

    if (current_index < 0) {
        gtk_list_box_unselect_all(GTK_LIST_BOX(panel->list));
        return;
    }

    GtkWidget *child = gtk_widget_get_first_child(panel->list);
    while (child != NULL) {
        gpointer indexData = g_object_get_data(G_OBJECT(child), "np-track-index");
        if ((int32_t)GPOINTER_TO_INT(indexData) == current_index) {
            gtk_list_box_select_row(GTK_LIST_BOX(panel->list), GTK_LIST_BOX_ROW(child));
            break;
        }
        child = gtk_widget_get_next_sibling(child);
    }
}

static inline int32_t np_linux_ui_playlist_panel_selected_index(void *playlist_panel) {
    NPLinuxPlaylistPanel *panel = (NPLinuxPlaylistPanel *)playlist_panel;
    return np_linux_ui_playlist_selected_index(panel);
}

static inline int32_t np_linux_ui_playlist_panel_selected_indices(
    void *playlist_panel,
    int32_t *buffer,
    int32_t buffer_count
) {
    NPLinuxPlaylistPanel *panel = (NPLinuxPlaylistPanel *)playlist_panel;
    if (panel == NULL || panel->list == NULL || buffer == NULL || buffer_count <= 0) {
        return 0;
    }

    GList *selectedRows = gtk_list_box_get_selected_rows(GTK_LIST_BOX(panel->list));
    int32_t count = 0;

    for (GList *cursor = selectedRows; cursor != NULL && count < buffer_count; cursor = cursor->next) {
        GtkListBoxRow *row = GTK_LIST_BOX_ROW(cursor->data);
        gpointer indexData = g_object_get_data(G_OBJECT(row), "np-track-index");
        buffer[count] = (int32_t)GPOINTER_TO_INT(indexData);
        count += 1;
    }

    g_list_free(selectedRows);
    return count;
}

static inline void np_linux_ui_playlist_show_context_menu(NPLinuxPlaylistPanel *panel, double x, double y) {
    if (panel == NULL || panel->root == NULL) {
        return;
    }

    if (panel->context_popover == NULL) {
        GtkWidget *popover = gtk_popover_new();
        gtk_widget_set_parent(popover, panel->root);

        GtkWidget *menuBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 4);
        gtk_widget_set_margin_top(menuBox, 8);
        gtk_widget_set_margin_bottom(menuBox, 8);
        gtk_widget_set_margin_start(menuBox, 8);
        gtk_widget_set_margin_end(menuBox, 8);

        gtk_box_append(GTK_BOX(menuBox), np_linux_ui_playlist_make_button(panel, "Play", NP_LINUX_UI_PLAYLIST_ACTION_PLAY_SELECTED));
        gtk_box_append(GTK_BOX(menuBox), np_linux_ui_playlist_make_button(panel, "Remove", NP_LINUX_UI_PLAYLIST_ACTION_REMOVE_SELECTED));
        gtk_box_append(GTK_BOX(menuBox), np_linux_ui_playlist_make_button(panel, "Crop", NP_LINUX_UI_PLAYLIST_ACTION_CROP_SELECTION));
        gtk_box_append(GTK_BOX(menuBox), np_linux_ui_playlist_make_button(panel, "Track Info", NP_LINUX_UI_PLAYLIST_ACTION_FILE_INFO));
        gtk_box_append(GTK_BOX(menuBox), np_linux_ui_playlist_make_button(panel, "Remove Dead", NP_LINUX_UI_PLAYLIST_ACTION_REMOVE_DEAD_FILES));
        gtk_box_append(GTK_BOX(menuBox), np_linux_ui_playlist_make_button(panel, "Clear", NP_LINUX_UI_PLAYLIST_ACTION_CLEAR));

        gtk_popover_set_child(GTK_POPOVER(popover), menuBox);
        panel->context_popover = popover;
    }

    GdkRectangle targetRect = { (int)x, (int)y, 1, 1 };
    gtk_popover_set_pointing_to(GTK_POPOVER(panel->context_popover), &targetRect);
    gtk_popover_popup(GTK_POPOVER(panel->context_popover));
}

static inline void np_linux_ui_run_until_all_windows_close(void) {
    while (g_list_model_get_n_items(G_LIST_MODEL(gtk_window_get_toplevels())) > 0) {
        g_main_context_iteration(NULL, TRUE);
    }
}
