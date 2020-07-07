// This sort of re-implements broccoli-sass-source-maps, or at least copies a
// bunch of code from it -- seems that most people want to compile ONE sass file
// for their app, and that's absolutely not how we roll over here.

// Anyway, here's my thinking: give it a pre-funnelled list of thing.scss files
// (with the _thing.scss partials already stripped out), and optionally some
// extra include paths, and have it compile all of them to thing.css files. Ask
// Sass itself what the dependencies for each file were, and use those for
// MultiFilter's caching/recompiling behavior.
// Gonna be lazy and expect only a single inputPath, ignoring others.

const MultiFilter = require('broccoli-multifilter');
// const compileSass = require('broccoli-sass-source-maps')(require('sass'));
const sass = require('sass');
const walkSync = require('walk-sync');
const RSVP = require('rsvp');
const path = require('path');
const mkdirp = require('mkdirp');
const fs = require('fs');
const writeFile = RSVP.denodeify(fs.writeFile);
// TODO gotta add these to package.json


class CompileAllScss extends MultiFilter {
    constructor(inputNodes, options) {
        super(inputNodes, options);
        options = options || {};

        let extraIncludePaths = options.includePaths || [];
        this.includePaths = [inputNodes, ...extraIncludePaths];

        this.renderSass = RSVP.denodeify(sass.render);
        this.sassOptions = {
            importer: options.importer,
            functions: options.functions,
            includePaths: this.includePaths,
            indentedSyntax: options.indentedSyntax,
            omitSourceMapUrl: options.omitSourceMapUrl,
            outputStyle: options.outputStyle,
            precision: options.precision,
            sourceComments: options.sourceComments,
            fiber: options.fiber
        };

    }

    async build() {
        // Ignoring more than one inputPath.
        let inputPath = this.inputPaths[0];
        let inputFiles = walkSync(inputPath).filter( inFile => inFile.split('.')[-1] === 'scss' );
        return this.buildAndCache(
            inputFiles,
            async (relativePath, outputDirectory) => {
                let fullInputPath = path.join(inputPath, relativePath);
                let fullOutputPath = path.join(outputDirectory, relativePath.replace(/\.scss$/, '.css'));

                // Make sure there's somewhere to put it
                mkdirp.sync(path.dirname(fullOutputPath));

                let sassOptions = {
                    file: fullInputPath,
                    outFile: fullOutputPath,
                };
                Object.assign(sassOptions, this.sassOptions);
                let result = await this.renderSass(sassOptions);

                // actually write it
                await writeFile(fullOutputPath, result.css);

                return {
                    dependencies: [
                        fullInputPath,
                        ...result.stats.includedFiles
                    ]
                };
            }
        )
    }
}

export default CompileAllScss;
