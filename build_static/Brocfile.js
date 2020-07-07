const { WatchedDir } = require('broccoli-source');
const Funnel = require('broccoli-funnel');
const merge = require('broccoli-merge-trees');
const uglify = require('broccoli-uglify-sourcemap');
const env = require('broccoli-env');

import myDirs from './get_dirs';
import CompileAllScss from './compile-all-scss';

export default () => {
  // let htdocs = new WatchedDir('../htdocs');
  let htdocs = merge(myDirs.htdocs.map( dir => new WatchedDir(dir) ), {overwrite: true});

  // Vanilla ES5 JS: send it through the ES5 uglifier, if in prod.
  let jsDir = new Funnel(htdocs, {
    srcDir: 'js',
    destDir: 'js'
  });
  if (process.env.NODE_ENV === 'production') {
    jsDir = uglify(jsDir);
  }

  // Vanilla CSS (plus some maybe weird stuff?): just set it down over there, don't jostle it too hard.
  let stcDir = new Funnel(htdocs, {
    srcDir: 'stc',
    destDir: 'stc'
  });

  // SCSS: cross our fingers lmao
  let scssDir = new Funnel(htdocs, {
    srcDir: 'scss',
    destDir: 'stc/css',
  });
  let scssOutput = new CompileAllScss(scssDir);

  return merge(jsDir, stcDir, scssOutput);
}
