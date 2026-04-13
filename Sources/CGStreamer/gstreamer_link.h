// Umbrella header for GStreamer Swift import.
// On Linux these headers are provided by the gstreamer1.0-dev packages.
#include <gst/gst.h>
#include <gst/audio/audio.h>
#include <gst/app/gstappsink.h>
#include <gst/pbutils/pbutils.h>
#include <glib.h>

// Swift-friendly single-property setters.
// g_object_set is C-variadic; Swift cannot pass a typed nil terminator
// through CVarArg, so we wrap each variant in a non-variadic inline.
static inline void np_g_object_set_string(gpointer obj, const gchar *name, const gchar *value) {
    g_object_set(obj, name, value, NULL);
}
static inline void np_g_object_set_double(gpointer obj, const gchar *name, gdouble value) {
    g_object_set(obj, name, value, NULL);
}
static inline void np_g_object_set_int(gpointer obj, const gchar *name, gint value) {
    g_object_set(obj, name, value, NULL);
}
static inline void np_g_object_set_bool(gpointer obj, const gchar *name, gboolean value) {
    g_object_set(obj, name, value, NULL);
}
static inline void np_g_object_set_pointer(gpointer obj, const gchar *name, gpointer value) {
    g_object_set(obj, name, value, NULL);
}
