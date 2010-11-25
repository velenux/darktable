#!/bin/sh

inputfile=$1
outputdir=$2
outputheader=metadata_gen.h
outputbody=metadata_gen.c

headerdefine=__$(echo -n $outputheader | tr '[:lower:].' '[:upper:]_')__
# header of the .h file
cat > $outputdir/$outputheader << EOF
/** generated file, do not edit! */

#ifndef $headerdefine
#define $headerdefine

typedef enum dt_metadata_t
{
EOF

# header of the .c file
cat > $outputdir/$outputbody << EOF
/** generated file, do not edit! */

#include <string.h>
#include "$outputheader"

dt_metadata_t dt_metadata_get_keyid(const char* key)
{
EOF

# iterate over the input
first=0
for line in $(cat $inputfile | grep -v "^#"); do
    enum=DT_METADATA_$(echo -n $line | tr '[:lower:]' '[:upper:]')
    key=darktable.$line
    length=$(echo -n $key | wc -c)
    if [ "$first" -ne 0 ]; then
        echo "," >> $outputdir/$outputheader
    fi
    echo -n "    $enum" >> $outputdir/$outputheader
    first=1

    cat >> $outputdir/$outputbody << EOF
    if(strncmp(key, "$key", $length) == 0)
        return $enum;
EOF

done

# end of the .h file
cat >> $outputdir/$outputheader << EOF

}
dt_metadata_t;

dt_metadata_t dt_metadata_get_keyid(const char* key);

#endif

EOF

# end of the .c file
cat >> $outputdir/$outputbody << EOF
    return -1;
}

EOF
