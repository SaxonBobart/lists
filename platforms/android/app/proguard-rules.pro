# SnakeYAML reflects on its own classes; keep them when minification is enabled.
-keep class org.yaml.snakeyaml.** { *; }
-dontwarn org.yaml.snakeyaml.**
