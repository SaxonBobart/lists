// placeholder — see ../README.md
namespace Lists {
    public class Application : Adw.Application {
        public Application () {
            Object (
                application_id: "io.github.saxonbobart.Lists",
                flags: GLib.ApplicationFlags.DEFAULT_FLAGS
            );
        }

        public override void activate () {
            // Real impl will construct Lists.Window and call present ()
            // once the Window class is implemented.
        }
    }
}
