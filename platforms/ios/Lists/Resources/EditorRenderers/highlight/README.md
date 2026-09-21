# Offline syntax highlighting

Highlight.js 11.12.0, BSD-3-Clause. Bundles the official language registry.
Generated from the checked-in entry.js using esbuild 0.28.2 (IIFE, global ListsHighlight, ES2018).
No runtime network access. Token offsets are UTF-16 and only affect text attributes.

Source: [Highlight.js](https://github.com/highlightjs/highlight.js), using the
[explicit-language API](https://highlightjs.readthedocs.io/en/latest/api.html).
`languages.json` contains `listLanguages()` entries with `getLanguage(id).name`
and `.aliases`; Mermaid is added by the native completion UI because its
rendering is handled by the separately bundled Mermaid renderer.

To regenerate, copy `entry.js` into a temporary build directory, install exact
`highlight.js@11.12.0` and `esbuild@0.28.2` dependencies there, then run:

```sh
./node_modules/.bin/esbuild entry.js --bundle --minify --format=iife --global-name=ListsHighlight --target=es2018 --outfile=highlight.min.js
node -e 'const fs=require("fs"),h=require("highlight.js");fs.writeFileSync("languages.json",JSON.stringify(h.listLanguages().map(id=>({id,name:h.getLanguage(id).name||id,aliases:h.getLanguage(id).aliases||[]})).sort((a,b)=>a.name.localeCompare(b.name)),null,2)+"\n")'
```

Copy the generated JS and registry here and retain the upstream LICENSE.
No build tool or npm dependency is required at app runtime.
