# Deliberately specific to Kinopolis's server-rendered film detail pages.
# Emit buyable OV performance IDs, never the OV legend outside a performance.
BEGIN { RS = "<" }
function attr(tag, name,    rest, quote, pos) {
    if (!match(tag, name "[[:space:]]*=[[:space:]]*[\042\047]")) return ""
    rest = substr(tag, RSTART + RLENGTH - 1)
    quote = substr(rest, 1, 1)
    rest = substr(rest, 2)
    pos = index(rest, quote)
    return pos ? substr(rest, 1, pos - 1) : ""
}
function hasclass(tag, name,    classes) {
    classes = attr(tag, "class")
    gsub(/[[:space:]]+/, " ", classes)
    return index(" " classes " ", " " name " ") > 0
}
{
    end = index($0, ">")
    if (!end) next
    tag = substr($0, 1, end - 1)
    if (tag ~ /^h1([[:space:]]|$)/) heading = 1
    if (tag ~ /^\/html[[:space:]]*$/) complete = 1
    if ($0 ~ /Aktuell keine Spielzeiten vorhanden/) empty = 1
    if (tag ~ /^div([[:space:]]|$)/) {
        depth++
        if (hasclass(tag, "prog2__cont")) {
            if (active) broken = 1
            active = depth
            id = attr(tag, "data-performance-id")
            ov = buy = 0
            count++
            if (id !~ /^[A-Za-z0-9_-]+$/) broken = 1
        }
    }
    if (active) {
        if (hasclass(tag, "tech__ov")) ov = 1
        if (tag ~ /^a([[:space:]]|$)/ && hasclass(tag, "buy__btn") &&
            attr(tag, "href") ~ ("/programm/vorstellung/" id "([?#].*)?$")) buy = 1
    }
    if (tag ~ /^\/div[[:space:]]*$/) {
        if (active == depth) {
            if (ov && buy && !broken) print id
            active = 0
        }
        depth--
    }
}
END {
    # Don't silently establish a baseline from a challenge/error/redesigned page.
    if (!heading || !complete || (!count && !empty) || active || broken) {
        print "Kinopolis HTML nicht erkannt oder unvollständig" > "/dev/stderr"
        exit 1
    }
}
