const hljs = require('highlight.js');
exports.tokens = function(source, language) {
  if (!hljs.getLanguage(language)) return [];
  const html = hljs.highlight(source, {language, ignoreIllegals:true}).value;
  const stack = [], tokens = [];
  let offset = 0;
  for (const match of html.matchAll(/<span class="([^"]*)">|<\/span>|([^<]+)/g)) {
    if (match[1] !== undefined) stack.push(match[1]);
    else if (match[0] === '</span>') stack.pop();
    else {
      const value = match[2].replace(/&(amp|lt|gt|quot|#x27|#39|#x[0-9a-f]+|#\d+);/gi, (_, e) => {
        const names = {amp:'&',lt:'<',gt:'>',quot:'"','#x27':"'",'#39':"'"};
        return names[e] || String.fromCodePoint(e[1].toLowerCase()==='x' ? parseInt(e.slice(2),16) : parseInt(e.slice(1),10));
      });
      if (stack.length) tokens.push({location:offset,length:value.length,scope:stack.join(' ')});
      offset += value.length;
    }
  }
  if (offset !== source.length) return [];
  return tokens;
};
