// @ts-check
import { defineEcConfig, ExpressiveCodeTheme } from '@astrojs/starlight/expressive-code';

// Code blocks in the Ultramarine & Marigold palette (src/styles/theme.css).
// Every token colour clears 4.5:1 on its block background.

/**
 * @param {{ name: string, type: 'dark' | 'light', bg: string, fg: string, keyword: string, constant: string,
 *   symbol: string, string: string, number: string, method: string, comment: string }} c
 */
function theme(c) {
  return new ExpressiveCodeTheme({
    name: c.name,
    type: c.type,
    colors: { 'editor.background': c.bg, 'editor.foreground': c.fg },
    tokenColors: [
      { scope: ['keyword', 'storage', 'keyword.control', 'keyword.operator'], settings: { foreground: c.keyword } },
      {
        scope: ['entity.name.type', 'support.class', 'variable.other.constant', 'entity.other.inherited-class'],
        settings: { foreground: c.constant },
      },
      {
        scope: ['constant.language.symbol', 'constant.other.symbol', 'constant.other.symbol.hashkey'],
        settings: { foreground: c.symbol },
      },
      { scope: ['string', 'punctuation.definition.string'], settings: { foreground: c.string } },
      { scope: ['constant.numeric', 'constant.language'], settings: { foreground: c.number } },
      { scope: ['entity.name.function', 'meta.function-call'], settings: { foreground: c.method } },
      { scope: ['comment', 'punctuation.definition.comment'], settings: { foreground: c.comment } },
    ],
  });
}

const dark = theme({
  name: 'ultramarine-dark', type: 'dark', bg: '#151a2c', fg: '#d5daeb', keyword: '#9eb0ff', constant: '#ffc978',
  symbol: '#6fd6c4', string: '#f4a3ba', number: '#ffb547', method: '#c4b4ff', comment: '#8c95b0',
});
const light = theme({
  name: 'ultramarine-light', type: 'light', bg: '#f2f4fb', fg: '#1b2033', keyword: '#2337d4', constant: '#8a4a00',
  symbol: '#0b6b61', string: '#a3234b', number: '#954b00', method: '#5a3db3', comment: '#5d6479',
});

/**
 * The site's examples end in `# => value`, and every one is checked in CI. As
 * plain comments they are the faintest text in a block, so this tags each
 * `# =>` comment span with `af-result` (styled in theme.css) to show it as a result.
 *
 * @returns {import('@astrojs/starlight/expressive-code').ExpressiveCodePlugin}
 */
function rubyResults() {
  /** @param {any} node */
  const walk = (node) => {
    if (node.type === 'element' && node.tagName === 'span') {
      const text = node.children?.length === 1 && node.children[0].type === 'text' ? node.children[0].value : '';
      if (/^\s*#\s*=>/.test(text)) {
        const cls = node.properties.className ?? [];
        node.properties.className = [...(Array.isArray(cls) ? cls : [cls]), 'af-result'];
        return;
      }
    }
    node.children?.forEach(walk);
  };
  return {
    name: 'ruby-results',
    hooks: {
      postprocessRenderedLine: ({ renderData }) => walk(renderData.lineAst),
    },
  };
}

export default defineEcConfig({
  themes: [dark, light],
  plugins: [rubyResults()],
  styleOverrides: { borderRadius: '0.375rem', codeFontSize: '0.875rem' },
});
