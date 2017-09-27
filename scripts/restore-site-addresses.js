'use strict';

const { assoc } = require('ramda');
const { DB } = require('./lib/db');

var content = '';

const parseLine = (line) => {
  try {
    if (!line.startsWith('SET     site:')) return;

    const cols = line.split(/[ ]+'/);
    const json = cols[1].substring(0, cols[1].length - 1);
    const site = JSON.parse(json);

    if (!site.id) throw new Error('No site ID');

    const siteName = site.identification ? site.identification.name : site.id;

    if (!site.description || (!site.description.address && !site.description.note)) {
      console.log(`No data for site ${siteName}`);
      return;
    }

    return DB.site.findById(site.id)
      .then((dbSite) => {
        const dbSiteName = dbSite.identification ? dbSite.identification.name : dbSite.id;
        let updatedSite = dbSite;
        if (site.description.address) {
          if (!dbSite.description || !dbSite.description.address) {
            updatedSite = assoc(['description', 'address'], site.description.address, dbSite);
            console.log(`Update address of site ${dbSiteName}`);
          } else {
            console.log(`Will not update address of site ${dbSiteName} - already set`);
          }
        }

        if (site.description.note) {
          if (!dbSite.description || !dbSite.description.note) {
            updatedSite = assoc(['description', 'note'], site.description.note, dbSite);
            console.log(`Updated note of site ${dbSiteName}`);
          } else {
            console.log(`Will not update note of site ${dbSiteName} - already set`);
          }
        }

        if (updatedSite !== dbSite) {
          return Promise.resolve() // DB.site.update(updatedSite)
            .then(`Updated site ${dbSiteName}`)
            .catch(err => console.log(`Failed to update site ${siteName}: ${err}`));
        }
      })
      .catch(err => console.log(err));


  } catch(err) {
    console.error(`Invalid line: ${line}`);
  }
};

const onData = (data) => {
  content += data.toString();
  const lines = content.split('\n');
  for (let i=0; i<lines.length - 1; i++) {
    parseLine(lines[i]);
  }
  content=lines[lines.length - 1];
};

const onEnd = () => {
  parseLine(content);
  process.exit(0);
};

process.stdin.resume();
process.stdin.setEncoding('utf-8');
process.stdin.on('data', onData);
process.stdin.on('end', onEnd);