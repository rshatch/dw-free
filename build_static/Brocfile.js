const { WatchedDir } = require('broccoli-source');
const Funnel = require('broccoli-funnel');
const merge = require('broccoli-merge-trees');
const uglify = require('broccoli-uglify-sourcemap');
const env = require('broccoli-env');
const Fiber = require('fibers');

import myDirs from './get_dirs';
import CompileAllScss from './compile-all-scss';

export default () => {
  // let htdocs = new WatchedDir('../htdocs');
  let htdocs = merge(myDirs.htdocs.map( dir => new WatchedDir(dir) ), {overwrite: true});

  // Images: whatever
  let imgDir = new Funnel(htdocs, {
    srcDir: 'img',
    destDir: 'img',
    annotation: 'Image dir (copy)',
  });

  // Vanilla ES5 JS: send it through the ES5 uglifier, if in prod.
  let jsDir = new Funnel(htdocs, {
    srcDir: 'js',
    destDir: 'js',
    annotation: 'JS dir (copy)',
  });
  if (process.env.NODE_ENV === 'production') {
    jsDir = uglify(jsDir, {
      annotation: 'JS dir (uglify)',
      mangle: false,
      compress: {
        defaults: true,
      },
    });
  }

  // Vanilla CSS (plus some maybe weird stuff?): just set it down over there, don't jostle it too hard.
  let stcDir = new Funnel(htdocs, {
    srcDir: 'stc',
    destDir: 'stc',
    annotation: 'stc dir (copy)',
  });

  // SCSS: start w/ an isolated working directory, so the include paths work out
  // more easily. Then compile to CSS, then move things to the expected final
  // location.
  let scssDir = new Funnel(htdocs, {
    srcDir: 'scss',
    destDir: '.',
    annotation: 'SCSS dir (copy to root)',
  });
  let sassOptions = {
    fiber: Fiber, // slightly faster.
    annotation: 'SCSS dir (convert all)',
  };
  if (process.env.NODE_ENV === 'production') {
    sassOptions.outputStyle = 'compressed';
  }
  let scssOutput = new CompileAllScss([scssDir], sassOptions);
  let scssFinal = new Funnel(scssOutput, {
    srcDir: '.',
    destDir: 'stc/css',
    annotation: 'SCSS dir (copy to stc/css)',
  });

  return merge([imgDir, jsDir, stcDir, scssFinal], {
    annotation: 'Final merge',
    overwrite: true,
  });
}
