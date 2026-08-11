// @tiptap/core/jsx-runtime@3.29.2 downloaded from https://ga.jspm.io/npm:@tiptap/core@3.29.2/jsx-runtime/index.js
//
// DIAGNOSTIC PATCH, not a tool-generated file: JSPM's CDN split this module's
// shared preact-style h()/Fragment helper into a separate chunk, referenced by
// a RELATIVE URL that only resolves on JSPM's own origin (../_/Bz2Filul.js).
// `bin/importmap pin` copies the file body verbatim without rewriting or
// following that reference, so the vendored file 404s on our own origin the
// instant it's imported. Inlined here (fetched once from
// https://ga.jspm.io/npm:@tiptap/core@3.29.2/_/Bz2Filul.js, ~250 bytes) only
// to find out whether this is the SOLE landmine in the graph before deciding
// whether vendoring tiptap is viable at all.
function F(e){return e.children}
function h(e,t){if(e===`slot`)return 0;if(e instanceof Function)return e(t);let{children:n,...r}=t==null?{}:t;if(e===`svg`)throw Error(`SVG elements are not supported in the JSX syntax, use the array syntax instead`);return[e,r,n]}

export{F as Fragment,h as createElement,h,h as jsx,h as jsxDEV,h as jsxs};

