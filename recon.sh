# Desired folder tree
# --/path/to/data -> DATA_DIR
# ----RawData.bin -> RAW_DATA_PATH
# --/path/to/save_reconstruction -> MODEL_DIR
# --/path/to/xr_workspace
# ----XRARdemo
# ------recon.sh
# ----XRSfm
# ----XRLocalization

DATA_DIR=''
RAW_DATA_PATH=''
MODEL_DIR=''

SFM_DIR=${MODEL_DIR}/sfm/
REFINE_DIR=${MODEL_DIR}/refine/
IMAGE_DIR=${DATA_DIR}/images
CAMERA_TXT=${DATA_DIR}/camera.txt

mkdir -p ${MODEL_DIR}
mkdir -p ${SFM_DIR}
mkdir -p ${REFINE_DIR}
mkdir -p ${IMAGE_DIR}

# unpacking data
echo 'Step 0: Unpacking data'
cd ../xrsfm
[[ -f ${CAMERA_TXT} ]] || ./bin/unpack_collect_data ${RAW_DATA_PATH} ${DATA_DIR}  || { echo 'unpacking data failed' ; exit 1; }

# setup database
echo 'Step 1: Setting up database'
cd ../XRLocalization
export PYTHONPATH=$PYTHONPATH:`pwd`

[[ -f ${SFM_DIR}/database.db ]] || python tools/ir_create_database.py --image_dir ${IMAGE_DIR} --database_path ${SFM_DIR}/database.db  || { echo 'create database failed' ; exit 1; }
[[ -f ${SFM_DIR}/retrieval.txt ]] || python tools/ir_image_retrieve.py --database_path ${SFM_DIR}/database.db --save_path ${SFM_DIR}/retrieval.txt  || { echo 'image retrieval failed' ; exit 1; }

# run sfm
echo 'Step 2: Running Sfm'
[[ -f ${SFM_DIR}/ftr.bin ]] || ./bin/run_matching ${IMAGE_DIR} ${SFM_DIR}/retrieval.txt sequential ${SFM_DIR}  || { echo 'sift matching failed' ; exit 1; }
[[ -f ${SFM_DIR}/images.bin ]] || ./bin/rec_seq ${SFM_DIR} ${IMAGE_DIR} ${CAMERA_TXT} ${SFM_DIR}  || { echo 'sequential recon failed' ; exit 1; }

# extract/match with superpoint
echo 'Step 3: Re-extract/match with superpoint'
cd ../XRLocalization
[[ -f ${SFM_DIR}/features.bin ]] || python tools/recon_feature_extract.py --image_dir ${IMAGE_DIR} --image_bin_path ${SFM_DIR}/images.bin --feature_bin_path ${SFM_DIR}/features.bin  || { echo 'extract superpoint failed' ; exit 1; }
[[ -f ${SFM_DIR}/matching.bin ]] || python tools/recon_feature_match.py --recon_path ${SFM_DIR} --feature_bin_path ${SFM_DIR}/features.bin --match_bin_path ${SFM_DIR}/matching.bin  || { echo 'matching superpoint failed' ; exit 1; }

# re-triangulate
echo 'Step 4: Re-triangulate'
cd ../xrsfm
[[ -f ${REFINE_DIR}/cameras.bin ]] || ./bin/run_triangulation ${SFM_DIR} ${SFM_DIR}/features.bin ${SFM_DIR}/matching.bin ${REFINE_DIR}  || { echo 'run triangulation failed' ; exit 1; }

# prepare for localization service
echo 'Step 5: Prepare for localization service'
cd ../XRLocalization
python tools/loc_convert_reconstruction.py --feature_path ${SFM_DIR}/features.bin --model_path ${REFINE_DIR} --output_path ${MODEL_DIR}  || { echo 'convert recon failed' ; exit 1; }
python tools/ir_create_database.py --image_dir ${IMAGE_DIR} --database_path ${MODEL_DIR}/database.bin --image_bin_path ${SFM_DIR}/images.bin  || { echo 'create database for loc server failed' ; exit 1; }


