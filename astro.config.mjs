// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import starlightLlmsTxt from 'starlight-llms-txt';

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
      // llms.txt, llms-full.txt and llms-small.txt for agents, plus one file per gem's reference.
      plugins: [
        starlightLlmsTxt({
          projectName: 'field_struct & actionable',
          details: [
            'field_struct (gem `field_struct`) gives Ruby POROs typed, coerced, validated fields with JSON round-trips.',
            'actionable (gem `actionable-rb`) builds typed service objects from steps that return declared outcomes.',
            'The runnable Ruby examples are executed in CI against the released gems, so `# => value` comments show real results.',
          ].join(' '),
          promote: ['index*', 'tutorial/**'],
          customSets: [
            { label: 'field_struct reference', paths: ['reference/field-struct/**'], description: 'every field_struct type, option and API' },
            { label: 'actionable reference', paths: ['reference/actionable/**'], description: 'every actionable macro, outcome and API' },
          ],
        }),
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
