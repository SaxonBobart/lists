// placeholder — see ../README.md
namespace Lists {
    [GtkTemplate (ui = "/io/github/saxonbobart/Lists/window.ui")]
    public class Window : Adw.ApplicationWindow {
        public Window (Application app) {
            Object (application: app);
        }
    }
}
