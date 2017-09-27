'use strict';

const { assocPath } = require('ramda');
const { DB } = require('./lib/db');

let content = '';
const promises = [];

const parseLine = (line) => {
  try {
    if (!line.startsWith('SET     site:')) return;

    const cols = line.split(/[ ]+'/);
    const json = cols[1].substring(0, cols[1].length - 1);
    const site = JSON.parse(json);

    if (!site.id) throw new Error('No site ID');

    const siteName = site.identification ? site.identification.name : site.id;

    if (!site.description || (!site.description.address && !site.description.note)) {
      console.log(`No address or note for site ${siteName} was found`);
      return Promise.resolve();
    }

    return DB.site.findById(site.id)
      .then((dbSite) => {
        const dbSiteName = dbSite.identification ? dbSite.identification.name : dbSite.id;
        let updatedSite = dbSite;
        if (site.description.address) {
          if (!dbSite.description || !dbSite.description.address) {
            updatedSite = assocPath(['description', 'address'], site.description.address, dbSite);
            console.log(`Will update address of site ${dbSiteName} to ${site.description.address}`);
          } else {
            console.log(`Will not update address of site ${dbSiteName} - already set`);
          }
        }

        if (site.description.note) {
          if (!dbSite.description || !dbSite.description.note) {
            updatedSite = assocPath(['description', 'note'], site.description.note, dbSite);
            console.log(`Will update note of site ${dbSiteName} to ${site.description.note}`);
          } else {
            console.log(`Will not update note of site ${dbSiteName} - already set`);
          }
        }

        if (updatedSite !== dbSite) {
          return DB.site.update(updatedSite)
            .then(() => console.log(`Updated site ${dbSiteName}`))
            .catch(err => console.log(`Failed to update site ${siteName}: ${err}`));
        }
      })
      .catch(err => console.log(`Error : ${err}`));

  } catch(err) {
    console.log(`Invalid line: ${line}`);
    console.log(err);
  }

  return Promise.resolve();
};

const onData = (data) => {
  content += data.toString();
  const lines = content.split('\n');
  for (let i=0; i<lines.length - 1; i++) {
    promises.push(parseLine(lines[i]));
  }
  content=lines[lines.length - 1];
};

const onEnd = () => {
  promises.push(parseLine(content));
  Promise.all(promises).then(() => {
    console.log('Script finished');
    process.exit(0);
  });
};

console.log('Script started');
process.stdin.resume();
process.stdin.setEncoding('utf-8');
process.stdin.on('data', onData);
process.stdin.on('end', onEnd);
