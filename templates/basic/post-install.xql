xquery version "3.0";

import module namespace pmu="http://www.tei-c.org/tei-simple/xquery/util";
import module namespace odd="http://www.tei-c.org/tei-simple/odd2odd";
import module namespace config="http://www.tei-c.org/tei-simple/config" at "modules/config.xqm";
import module namespace tpu="http://www.tei-c.org/tei-publisher/util" at "util.xql";

declare namespace repo="http://exist-db.org/xquery/repo";

(: The following external variables are set by the repo:deploy function :)

(: file path pointing to the exist installation directory :)
declare variable $home external;
(: path to the directory containing the unpacked .xar package :)
declare variable $dir external;
(: the target collection into which the app is deployed :)
declare variable $target external;


declare variable $repoxml :=
    let $uri := doc($target || "/expath-pkg.xml")/*/@name
    let $repo := util:binary-to-string(repo:get-resource($uri, "repo.xml"))
    return
        parse-xml($repo)
;

declare function local:mkcol-recursive($collection, $components) {
    if (exists($components)) then
        let $newColl := concat($collection, "/", $components[1])
        return (
            if (not(xmldb:collection-available($collection || "/" || $components[1]))) then
                let $created := xmldb:create-collection($collection, $components[1])
                return (
                    sm:chown(xs:anyURI($created), $repoxml//repo:permissions/@user),
                    sm:chgrp(xs:anyURI($created), $repoxml//repo:permissions/@group),
                    sm:chmod(xs:anyURI($created), replace($repoxml//repo:permissions/@mode, "(..).(..).(..).", "$1x$2x$3x"))
                )
            else
                (),
            local:mkcol-recursive($newColl, subsequence($components, 2))
        )
    else
        ()
};

(: Helper function to recursively create a collection hierarchy. :)
declare function local:mkcol($collection, $path) {
    local:mkcol-recursive($collection, tokenize($path, "/"))
};

declare function local:create-data-collection() {
    if (xmldb:collection-available($config:data-root)) then
        ()
    else if (starts-with($config:data-root, $target)) then
        local:mkcol($target, substring-after($config:data-root, $target || "/"))
    else
        ()
};


declare function local:generate-code($collection as xs:string) {
    for $source in xmldb:get-child-resources($collection || "/resources/odd")[ends-with(., ".odd")][not(.=("teipublisher.odd", "tei_simplePrint.odd"))]
    let $odd := doc($collection || "/resources/odd/" || $source)
    let $pi := tpu:parse-pi($odd, (), $source)
    for $module in
        if ($pi?output) then
            tokenize($pi?output)
        else
            ("web", "print", "latex", "epub")
    for $file in pmu:process-odd (
        (:    $odd as document-node():)
        odd:get-compiled($collection || "/resources/odd" , $source),
        (:    $output-root as xs:string    :)
        $collection || "/transform",
        (:    $mode as xs:string    :)
        $module,
        (:    $relPath as xs:string    :)
        "../transform",
        (:    $config as element(modules)?    :)
        doc($collection || "/resources/odd/configuration.xml")/*)?("module")
    return
        (),
    let $permissions := $repoxml//repo:permissions[1]
    return (
        for $file in xmldb:get-child-resources($collection || "/transform")
        let $path := xs:anyURI($collection || "/transform/" || $file)
        return (
            sm:chown($path, $permissions/@user),
            sm:chgrp($path, $permissions/@group)
        )
    )
};

sm:chmod(xs:anyURI($target || "/modules/view.xql"), "rwxr-Sr-x"),
(:sm:chmod(xs:anyURI($target || "/modules/transform.xql"), "rwsr-xr-x"),:)
sm:chmod(xs:anyURI($target || "/modules/lib/pdf.xql"), "rwsr-xr-x"),
sm:chmod(xs:anyURI($target || "/modules/lib/get-epub.xql"), "rwsr-xr-x"),
sm:chmod(xs:anyURI($target || "/modules/lib/components.xql"), "rwsr-xr-x"),
sm:chmod(xs:anyURI($target || "/modules/lib/components-odd.xql"), "rwxr-Sr-x"),
sm:chmod(xs:anyURI($target || "/modules/lib/regenerate.xql"), "rwsr-xr-x"),
sm:chmod(xs:anyURI($target || "/modules/lib/app-download.xql"), "rwsr-xr-x"),
sm:chmod(xs:anyURI($target || "/modules/lib/dts.xql"), "rwsr-xr-x"),
(: sm:chmod(xs:anyURI($target || "/modules/lib/upload.xql"), "rwsr-xr-x"), :)

(: LaTeX requires dba permissions to execute shell process :)
sm:chmod(xs:anyURI($target || "/modules/lib/latex.xql"), "rwxr-Sr-x"),
sm:chgrp(xs:anyURI($target || "/modules/lib/latex.xql"), "dba"),

local:mkcol($target, "transform"),
local:generate-code($target),
local:create-data-collection()
