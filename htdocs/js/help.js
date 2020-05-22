$(function() {
var $table = $("table").stupidtable();

      $table.on("aftertablesort", function (event, data) {
        var th = $(this).find("th");
        th.find(".arrow").remove();
        var dir = $.fn.stupidtable.dir;

        var arrow = data.direction === dir.ASC ? "⯅" : "⯆";
        th.eq(data.column).append('<span class="arrow">' + arrow +'</span>');
      });

var params = new URLSearchParams(location.search);
var sort = params.get('sort');

if (sort) {
      var $th_to_sort = $table.find("thead th").filter('[data-name=' + sort + ']');
$th_to_sort.stupidsort();
}
$('#cat').change(function(ev) {
var cat = this.value;
if (cat == 'all') {
$('.supporttable tbody tr').show();
} else {
$('.supporttable tbody tr').hide();
$('.supporttable tbody tr.' + cat).show();
}
});

$('#state').change(function(ev) {
var state = this.value;
if (state == 'open') {
$('.supporttable tbody tr').show();
$('.supporttable tbody tr.red').hide();
} else if (state == 'green') {
$('.supporttable tbody tr').hide();
$('.supporttable tbody tr.green').show();
} else if (state == 'closed') {
$('.supporttable tbody tr').hide();
$('.supporttable tbody tr.red').show();
}
})

});