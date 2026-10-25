// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// Served by GitHub Pages as a project site: https://paymentbox-com.github.io/field_struct/
export default defineConfig({
  site: 'https://paymentbox-com.github.io',
  base: '/field_struct',
  integrations: [
    starlight({
      title: 'FieldStruct & Actionable',
      description: 'Typed POROs and typed service objects for Ruby.',
      social: [
        { icon: 'github', label: 'field_struct on GitHub', href: 'https://github.com/Paymentbox-com/field_struct' },
      ],
      sidebar: [
        { label: 'Tutorial', items: [{ autogenerate: { directory: 'tutorial' } }] },
        { label: 'How-to guides', items: [{ autogenerate: { directory: 'how-to' } }] },
        { label: 'Reference', items: [{ autogenerate: { directory: 'reference' } }] },
        { label: 'Explanation', items: [{ autogenerate: { directory: 'explanation' } }] },
      ],
    }),
  ],
});
