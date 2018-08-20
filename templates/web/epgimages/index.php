<?php
$epg_file = '/data/cache/images.data';
$e = isset($_GET['e']) ? intval($_GET['e']) : false;

if (!$e) {
    exit;
}

if (file_exists($epg_file)) {
    $handle = fopen($epg_file, "r");
    if ($handle) {
        $image = null;

        $epg_number_found = false;
        while (($line = fgets($handle)) !== false) {
            if ($line) {
                list($epgid, $image) = explode(' ', $line);
                if ($epgid == $e) {
                    get_image($image);
                }
            }
        }

        fclose($handle);
    }
}

default_image();

function get_image($url = NULL)
{
    $url = trim($url);
    $ext = substr($url, strrpos($url, '.') + 1);

    header('Content-Type: image/' . $ext);
    echo readfile($url);
    exit;
}

function default_image()
{
    header('Content-Type: image/jpg');
    readfile('./default.jpg');
    exit;

}