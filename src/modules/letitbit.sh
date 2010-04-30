#!/bin/bash
#
# Letitbit.net module for plowshare
# Author Pavel Alexeev <Pahan@hubbitus.info>
#
# Distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Plowshare.  If not, see <http://www.gnu.org/licenses/>.

MODULE_LETITBIT_REGEXP_URL="http://\(www\.\)\?letitbit\.net/"
MODULE_LETITBIT_DOWNLOAD_OPTIONS=""
MODULE_LETITBIT_UPLOAD_OPTIONS=
MODULE_LETITBIT_DOWNLOAD_CONTINUE=no

# letitbit_download [DOWNLOAD_OPTIONS] URL
# I have not pay account and only free download implemented. Feel free contact
# me if you want gold download and can sponsor me login and pass
# Output file URL
#
letitbit_download() {
    set -e
    eval "$(process_options letitbit "$MODULE_LETITBIT_DOWNLOAD_OPTIONS" "$@")"

    URL=$1
    BASEURL="http://letitbit.net"
    WAITTIME=60
    COOKIES=$(create_tempfile)

    echo $URL | grep -q "letitbit.net" ||
            URL=$(curl -I "$URL" | grep_http_header_location)

    TRY=0
    while retry_limit_not_reached || return 3; do
        (( TRY++ ))
        log_debug "Downloading first page (loop $TRY)"
        PAGE=$(curl -c $COOKIES "$URL") || { echo "Error getting page: $URL"; return 1; }
        uid=$(echo "$PAGE" | parse '\"uid\"' 'value=\"\(.*\)\"' 2>/dev/null || true)
        md5crypt=$(echo "$PAGE" | parse '\"md5crypt\"' 'value=\"\(.*\)\"' 2>/dev/null || true)
        test "$uid" || { log_error "Error parse uid and md5crypt"; return 1; }
        # 'fix' set by JavaScript, manually set it to 1
        data="uid=$uid&md5crypt=$md5crypt&fix=1"
        log_debug "Data: $data";
        # @TODO error handling
        #debug DeBase64: $( echo $md5crypt | base64 -d )

        PAGE=$(curl -b $COOKIES --data "$data" "$BASEURL/download4.php")
        uid=$(echo "$PAGE" | parse '\"uid\"' 'value=\"\(.*\)\"' 2>/dev/null || true)
        md5crypt=$(echo "$PAGE" | parse '\"md5crypt\"' 'value=\"\(.*\)\"' 2>/dev/null || true)

        CAPTCHA_URL=$(echo "$PAGE" | parse 'cap.php?jpg=' "\(cap.php?jpg=[^']\+\)'" ) ||
            { log_error 'Captcha URL not found'; return 1; }

        if test "$CHECK_LINK"; then
            rm -f $COOKIES
            return 255
        fi

        log_debug "captcha URL: $CAPTCHA_URL"

        # OCR captcha and show ascii image to stderr simultaneously
        CAPTCHA=$(curl -b $COOKIES "$BASEURL/$CAPTCHA_URL" | show_image_and_tee |
                convert -contrast-stretch 0%x74% -threshold 80% -crop '59x19+1+1' +repage jpg:- pbm:- |
                gocr_ocr | sed 's/ //g' ) ||
            { log_error "running OCR"; return 1; }
        log_debug "Decoded captcha: $CAPTCHA"
        test $(echo -n $CAPTCHA | wc -c) -eq 6 ||
            { log_debug "Captcha length invalid"; continue; }

        data="cap=$CAPTCHA&uid2=$uid&md5crypt=$md5crypt&fix=1"
        log_debug "Data: $data";
        WAITPAGE=$(curl -b $COOKIES --data "$data" "$BASEURL/download3.php" 2>/dev/null )
        # <span name="errt" id="errt">60</span>
        FILEURL=$(echo "$WAITPAGE" | parse 'link=' 'link=\([^\"]\+\)\"' 2>/dev/null || true)
        test "$FILEURL" && break;
        log_debug 'Wrong captcha, retry'
    done

    log_debug "Correct captch (try $TRY)"
    rm -f $COOKIES

    # wait is not necessary, we can download instantly!
    echo "$FILEURL"
}

# OCR of an image. Write OCRed text to standard input
# For ocr gocr is used.
#
# Standard input: image
gocr_ocr(){
    gocr -
}
