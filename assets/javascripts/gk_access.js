// gk_access: where the lock by Private stands (Appearance, The explanation by Private). The server draws each lock where
// Redmine's hook stands, and the lock names where it belongs by an id Redmine gives its own element:
//   data-gk-access-after="<id>"  a note's lock as an icon only: after the note's badge Private in its head. A lock on a
//                                fold list (GK GUI Stuff's slot) stays there, the slot takes a lock from where it stands
//                                when the bar comes later, and a lock whose bar has gone comes back here.
//   data-gk-access-into="<id>"   the issue form's lock: last in the row of the check box Private;
//   data-gk-access-tip="<ids>"   the elements that get the explanation as their tooltip too (the box and its label).
//   data-gk-access-by="<id>"     the lock by the check box for private notes: after the box and its labels, which also
//                                get the explanation as their tooltip.
// The lock on an issue is not moved: the server draws it by the hook after the issue's head. Plain DOM. The script is
// loaded only with GK GUI Stuff (the explanation is closed without it), whose kernel runs place again whenever the
// page's content changes, as when Redmine draws the issue form anew.
(function () {
  // the explanation is the popover's label, which GK GUI Stuff makes the lock's tooltip; a tooltip that already says
  // it is left alone, so that nothing changes on a pass with nothing to do
  function tip(lock, els) {
    var summary = lock.querySelector('summary');
    var line = summary ? summary.title : '';
    if (!line) return;
    els.forEach(function (el) { if (el && el.title !== line) el.title = line; });
  }

  function place() {
    document.querySelectorAll('.gk-access-private-lock[data-gk-access-after]').forEach(function (lock) {
      if (lock.closest('.gk-gui-stuff-fold-slot')) return;
      var badge = document.getElementById(lock.getAttribute('data-gk-access-after'));
      if (badge && badge.nextElementSibling !== lock) badge.insertAdjacentElement('afterend', lock);
    });
    document.querySelectorAll('.gk-access-private-lock[data-gk-access-into]').forEach(function (lock) {
      var row = document.getElementById(lock.getAttribute('data-gk-access-into'));
      if (!row) return;
      if (!row.contains(lock)) row.appendChild(lock);
      tip(lock, (lock.getAttribute('data-gk-access-tip') || '').split(' ').map(function (id) { return id ? document.getElementById(id) : null; }));
    });
    document.querySelectorAll('.gk-access-private-lock[data-gk-access-by]').forEach(function (lock) {
      // the check box by the id core's form builder gives it; its labels by the browser's own association
      // (box.labels: for= or a label round the box), never by how core nests or orders them
      var box = document.getElementById(lock.getAttribute('data-gk-access-by'));
      if (!box) return;
      var labels = Array.prototype.slice.call(box.labels || []);
      // the lock stands after the box and its labels, whichever of them comes last in the page
      var last = box;
      labels.forEach(function (l) {
        if (l.contains(box) || (last.compareDocumentPosition(l) & Node.DOCUMENT_POSITION_FOLLOWING)) last = l;
      });
      if (last.nextElementSibling !== lock) last.insertAdjacentElement('afterend', lock);
      tip(lock, [box].concat(labels));
    });
  }

  function start() {
    place();
    window.GkGui.onContent(place);
    document.addEventListener('gk-gui-fold-slot-left', place);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();
