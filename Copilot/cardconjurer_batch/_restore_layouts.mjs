import fs from 'fs';
import path from 'path';

const templatesDir = 'c:/Users/hecke/Desktop/Mtg-Roles/Cards/templates';
const src = path.join(templatesDir, 'Assassin_Layout.cardconjurer');
const raw = fs.readFileSync(src, 'utf8');

for (const role of ['Bandit', 'Guardian', 'King', 'Renegade']) {
  const dest = path.join(templatesDir, `${role}_Layout.cardconjurer`);
  const updated = raw.replace('"Assassin_Layout"', `"${role}_Layout"`);
  fs.writeFileSync(dest, updated, 'utf8');
  console.log(`${role}: created`);
}
