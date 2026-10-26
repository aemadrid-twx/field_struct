// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// Served by GitHub Pages from the aemadrid-twx/field_struct fork (ruling R21): https://aemadrid-twx.github.io/field_struct/
export default defineConfig({
  site: 'https://aemadrid-twx.github.io',
  base: '/field_struct',
  integrations: [
    starlight({
      title: 'FieldStruct & Actionable',
      description: 'Typed POROs and typed service objects for Ruby.',
      logo: { src: './src/assets/brand/pair.svg', alt: 'field_struct and actionable' },
      head: [
        { tag: 'link', attrs: { rel: 'apple-touch-icon', href: '/field_struct/brand/apple-touch-icon.png' } },
      ],
      customCss: [
        '@fontsource-variable/instrument-sans',
        '@fontsource-variable/bricolage-grotesque',
        '@fontsource-variable/jetbrains-mono',
        './src/styles/theme.css',
      ],
      social: [
        { icon: 'github', label: 'field_struct on GitHub', href: 'https://github.com/aemadrid-twx/field_struct' },
      ],
      sidebar: [
        { label: 'Tutorial', items: [{ autogenerate: { directory: 'tutorial' } }] },
        { label: 'How-to guides', items: [{ autogenerate: { directory: 'how-to' } }] },
        {
          label: 'Reference',
          items: [
            { label: 'Overview', slug: 'reference' },
            { label: 'field_struct', items: [{ autogenerate: { directory: 'reference/field-struct' } }] },
            { label: 'actionable', items: [{ autogenerate: { directory: 'reference/actionable' } }] },
          ],
        },
        { label: 'Explanation', items: [{ autogenerate: { directory: 'explanation' } }] },
      ],
    }),
  ],
});
