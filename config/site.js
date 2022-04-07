NodeList.prototype.map = function(f,a){
    for(var i=0, l=this.length; i<l; i++)
	f.apply(this[i],a);
    return this;
};
document.addEventListener("DOMContentLoaded", function(){
    // construct node-ring
    var first = null;
    var last = null;
    document.querySelectorAll('a[id]').map(function(e){
	if(!first)
	    first = this;	
	if(last){ // link to prior node
	    this.setAttribute('prev', last.getAttribute('id'));
	    last.setAttribute('next', this.getAttribute('id'));
	};
	last = this;
    });
    if(first && last){ // close ring
	last.setAttribute('next',first.getAttribute('id'));
	first.setAttribute('prev',last.getAttribute('id'));
    };
    // keyboard control
    document.addEventListener("keydown",function(e){
	var key = e.keyCode;
	var selectNextLink = function(){
	    var cur = null;
	    if(window.location.hash)
		cur = document.getElementById(location.hash.slice(1));
	    if(!cur)
		cur = last;
	    window.location.hash = cur.getAttribute('next');
	    e.preventDefault();
	};
	var selectPrevLink = function(){
	    var cur = null;
	    if(window.location.hash)
		cur = document.getElementById(location.hash.slice(1));
	    if(!cur)
		cur = first;
	    window.location.hash = cur.getAttribute('prev');;
	    e.preventDefault();
	};
	var gotoLink = function(arc) {
	    var doc = document.querySelector("link[rel='" + arc + "']");
	    if(doc)
		window.location = doc.getAttribute('href');
	};
	if(e.getModifierState("Shift")) {
	    if(key==37) // [shift-left] previous page
		gotoLink('prev');
	    if(key==39) // [shift-right] next page
		gotoLink('next');
	    if(key==38) // [shift-up] up to parent
		gotoLink('up');
	    if(key==40) // [shift-down] down to children
		gotoLink('down');
	} else {
	    if(key==80) // [p]revious anchor
		selectPrevLink();
	    if(key==78) // [n]ext anchor
		selectNextLink();
	};
    },false);
    document.querySelectorAll('input').map(function(i){
	this.addEventListener("keydown",function(e){
	    e.stopPropagation();
	},false);
    });
}, false);
inlineplayer = function(player, vid){
    document.querySelector(player).innerHTML = "<iframe width='640' height='480' src='https://www.youtube.com/embed/" + vid + "?autoplay=1' frameborder='0' allow='accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture' allowfullscreen='true'></iframe>";
};
