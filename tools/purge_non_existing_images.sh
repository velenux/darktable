#!/bin/bash

# purge from Darktable database the references to images that are not
# available on disk anymore

# DEBUG
#set -x

# paths to commands we require
BIN_SQLITE=/usr/bin/sqlite3

# default paths for the library.db file
PATHS_DB="${HOME}/.var/app/org.darktable.Darktable/config/darktable/library.db ${HOME}/.config/darktable/library.db"


# temporary files
FILE_TMP_DB=$(mktemp)
FILE_TMP_QUERY=$(mktemp)
FILE_LIST_IMAGES=$(mktemp)


# cleanup function
cleanup_files () {
  echo "Cleaning up temporary files..."
  rm -f "${FILE_TMP_DB}" "${FILE_TMP_QUERY}" "${FILE_LIST_IMAGES}"
}

# run the cleanup routine before exiting
trap 'exit 1' INT QUIT TERM
trap cleanup_files EXIT


# check that we have all the binaries we need
if [ ! -x "${BIN_SQLITE}" ]; then
  echo "The command 'sqlite3' is missing. Please install it or change this script to point to the correct binary!"
  exit 1
fi


# ask the user for the path where the images are stored
read -p "Please specify the path to where your photos are stored on disk [default: ${HOME}]: " DIR_IMAGES
if [ -z "${DIR_IMAGES}" ]; then
  DIR_IMAGES=${HOME}
fi

# exit if the target directory does not exist
if [ ! -d "$DIR_IMAGES" ]; then
  echo "The directory you specified (${DIR_IMAGES}) does not seem to exist, exiting."
  exit 1
fi


# cycle over the default DB files until you find a valid one
for file_db in $PATHS_DB ; do
  if [ -f "$file_db" ]; then
    echo "Using '${file_db}' as target database."
    FILE_SRC_DB="${file_db}"
    break
  fi
done

# if we didn't find the DB, try asking the user
if [ -z "${FILE_SRC_DB}" ]; then
  # ask the user for the path to the DB file
  read -p "Please specify the path to Darktable DB file: " FILE_SRC_DB
fi

# exit if the DB file is not readable
if [ ! -r "${FILE_SRC_DB}" ]; then
  echo "It seems we can't read the DB file '${FILE_SRC_DB}', exiting!"
  exit 1
fi


# create a list of files available on disk
echo "Creating a list of files available in ${DIR_IMAGES}, this may take a while..."
find ${DIR_IMAGES} -type f -print > "$FILE_LIST_IMAGES"


# create a working copy of the DB
cp "${FILE_SRC_DB}" "${FILE_TMP_DB}"
sync


# extract the files and IDs from the database
echo "Querying the database for all the files it knows"
${BIN_SQLITE} ${FILE_TMP_DB} "select A.id,B.folder,A.filename from images as A join film_rolls as B on A.film_id = B.id" > "${FILE_TMP_QUERY}"
RET="$?"
if [ "${RET}" != 0 ]; then
  echo "An error occurred while querying the database, exiting."
  exit 1
fi

ID_LIST=""
COUNTER=0

# cycle over the files
echo "Checking the files in the DB against those on disk, this might take a while..."
while read -r entry ; do
  IMG_DIR=$(echo "$entry" | cut -d"|" -f2)
  IMG_FILENAME=$(echo "$entry" | cut -d"|" -f3)

  # check if the file is available on disk
  if ! grep "^${IMG_DIR}/${IMG_FILENAME}$" "${FILE_LIST_IMAGES}" &>/dev/null ; then
    IMG_ID=$(echo "$entry" | cut -d"|" -f1)
    ID_LIST="${ID_LIST},${IMG_ID}" # add the image ID to the list
    COUNTER=$(( $COUNTER + 1 ))
  fi
done < "${FILE_TMP_QUERY}"


echo "${COUNTER} broken entries to remove."

# cleanup the ID_LIST string from the trailing comma
ID_LIST=$(echo ${ID_LIST}|cut -c 2-)


# cleanup images and meta_data tables
for table in images meta_data; do
    $BIN_SQLITE "$FILE_TMP_DB" "delete from $table where id IN (${ID_LIST})"
    RET="$?"
    if [ "${RET}" != 0 ]; then
      echo "An error occurred while querying the database, exiting."
      exit 1
    fi
done


# cleanup color_labels, history, mask, selected_images and tagged_images tables
for table in color_labels history mask selected_images tagged_images; do
    $BIN_SQLITE "$FILE_TMP_DB" "delete from $table where imgid IN (${ID_LIST})"
    RET="$?"
    if [ "${RET}" != 0 ]; then
      echo "An error occurred while querying the database, exiting."
      exit 1
    fi
done


# delete now-empty filmrolls
$BIN_SQLITE "$FILE_TMP_DB" "DELETE FROM film_rolls WHERE (SELECT COUNT(A.id) FROM images AS A WHERE A.film_id=film_rolls.id)=0"
RET="$?"
if [ "${RET}" != 0 ]; then
  echo "An error occurred while querying the database, exiting."
  exit 1
fi


# make a backup of the original DB
echo "Backing up the original database"
FILE_BKP_DB="${HOME}/library-$(date +%s).db"
cp -v "${FILE_SRC_DB}" "${FILE_BKP_DB}"
RET="$?"
if [ "${RET}" != 0 ]; then
  echo "An error occurred while backing up the database, exiting."
  exit 1
fi


echo "Updating Darktable DB"
mv -f "${FILE_TMP_DB}" "${FILE_SRC_DB}"
RET="$?"
if [ "${RET}" != 0 ]; then
  echo "An error occurred while updating the database, a backup is available at ${FILE_BKP_DB}."
  exit 1
fi
