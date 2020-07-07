const { WatchedDir } = require('broccoli-source');
const Funnel = require('broccoli-funnel');
const merge = require('broccoli-merge-trees');
const uglify = require('broccoli-uglify-sourcemap');
const env = require('broccoli-env');

import myDirs from './get_dirs';

export default () => {
  // let htdocs = new WatchedDir('../htdocs');
  let htdocs = merge(myDirs.htdocs.map( dir => new WatchedDir(dir) ), {overwrite: true});

  let jsSubdir = new Funnel(htdocs, {
    srcDir: 'js',
    destDir: 'js'
  });
  if (process.env.NODE_ENV === 'production') {
    jsSubdir = uglify(jsSubdir);
  }
  return jsSubdir;
}
