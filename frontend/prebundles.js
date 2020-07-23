// This is dead code for now, I'm just doing stuff in json for the time being.

let prebundles = {
    base_jquery_js: [
        'js/jquery/jquery-1.8.3.js',
        'js/jquery/jquery.ui.core.js',
        'js/jquery/jquery.ui.widget.js',
        'js/jquery/jquery.ui.dialog.js',
        'js/dw/dw-core.js',

    ],

    base_jquery_css: [
        'stc/lj_base.css',
        'stc/jquery/jquery.ui.core.css',
        'stc/jquery/jquery.ui.dialog.css',

    ],

    base_foundation_js: [
        'js/jquery/jquery-1.8.3.js',
        'js/foundation/vendor/custom.modernizr.js',
        'js/foundation/foundation/foundation.js',
        'js/foundation/foundation/foundation.reveal.js',
        'js/foundation/foundation/foundation.topbar.js',
        'js/dw/dw-core.js',

        'js/jquery/jquery.ui.core.js',
        'js/jquery/jquery.ui.widget.js',
        'js/jquery/jquery.ui.tooltip.js',
        'js/jquery/jquery.ui.button.js',
        'js/jquery/jquery.ui.dialog.js',
        'js/jquery/jquery.ui.position.js',
        'js/jquery.ajaxtip.js',

        'js/jquery.hoverIntent.js',
        'js/jquery.contextualhover.js',

    ],

    base_foundation_nonskin_css: [
        'stc/lj_base.css',
        'stc/esn.css',
        'stc/css/foundation/foundation_minimal.css',

        'stc/jquery/jquery.ui.core.css',
        'stc/jquery/jquery.ui.tooltip.css',
        'stc/jquery/jquery.ui.button.css',
        'stc/jquery/jquery.ui.dialog.css',

        'stc/jquery/jquery.ui.theme.smoothness.css',

        'stc/jquery.contextualhover.css',
    ],

    base_foundation_siteskins_js: [
        // Needs to differ per each skin, right? Or what?
    ],

    base_foundation_siteskins_css: [
        'stc/lj_base.css',
        'stc/esn.css',

    ],

    base_6alib_js: [
        'js/6alib/core.js',
        'js/6alib/dom.js',
        'js/6alib/httpreq.js',
        'js/livejournal.js',

        'js/esn.js',
        'js/6alib/ippu.js',
        'js/lj_ippu.js',
        'js/6alib/hourglass.js',
        'js/contextualhover.js',

        'js/6alib/json.js',
        'js/6alib/template.js',
        'js/6alib/inputcomplete.js',
        'js/6alib/datasource.js',
        'js/6alib/selectable_table.js',

    ],

    base_6alib_css: [
        'stc/esn.css',
        'stc/lj_base.css',
        'stc/contextualhover.css',

    ],

    journal_content_js: [
        'js/jquery.esn.js',
        'js/jquery.replyforms.js',
        'js/jquery.poll.js',
        'js/journals/jquery.tag-nav.js',
        'js/jquery.mediaplaceholder.js',
        'js/jquery.imageshrink.js',
        'js/jquery.quickreply.js',
        'js/jquery.threadexpander.js',
        'js/jquery.talkform.js',
        'js/jquery.cuttag-ajax.js',
        'js/jquery.default-editor.js',
        'js/jquery.commentmanage.js',


    ],

    journal_content_css: [
        'stc/css/components/quick-reply.css',
        'stc/css/components/talkform.css',
        'stc/css/components/imageshrink.css',
        'stc/jquery.commentmanage.css',
    ],

    journal_shortcut_js: [
        "js/shortcuts.js",
        "js/jquery.shortcuts.nextentry.js",
        // Wait, actually this is absolute chaos. It string interpolates to generate some inline js to dump into the <head>, and excludes some scripts if some options aren't set. Need to dig deeper here and probably refactor some shit. (Can we just assign those shortcut keys to the Site object? or nah? --looks like site object has a ton of stuff that's just sitewide user settings, yeah? like opt_ctxpopup_icons/userhead. Perfect spot for it.)
    ],

    icon_browser_js: [
        'js/components/jquery.icon-browser.js',
    ],

    icon_browser_css: [
        'stc/css/components/icon-browser.css',
    ],

    icon_browser_old_js: [
        'js/jquery.iconselector.js',
    ],

    icon_browser_old_css: [
        'stc/jquery.iconselector.css',
    ],

    icon_browser_oldold_js: [
        'js/userpicselect.js',
    ],

    icon_browser_oldold_css: [
        'stc/ups.css',
    ],


}

