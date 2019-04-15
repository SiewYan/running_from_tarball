#!/bin/bash

###########
# setup
export BASEDIR=`pwd`

echo "base area"
ls -lhrt

############
# inputs

export VO_CMS_SW_DIR=/cvmfs/cms.cern.ch
source $VO_CMS_SW_DIR/cmsset_default.sh
source inputs.sh

export nevent="1000"

# output
#export EOSOUTPUT=${eos_output}

#
#############
#############
# make a working area
 
echo " Start to work now"
pwd
mkdir -p ./work
cd    ./work
export WORKDIR=`pwd`

#
#############
#############
# generate LHEs

#export SCRAM_ARCH=slc6_amd64_gcc481
#CMSSWRELEASE=CMSSW_7_1_20_patch3
export SCRAM_ARCH=slc6_amd64_gcc472
CMSSWRELEASE=CMSSW_7_1_30
scram p CMSSW $CMSSWRELEASE
cd $CMSSWRELEASE/src
mkdir -p Configuration/GenProduction/python/
cp ${BASEDIR}/inputs/${HADRONIZER} Configuration/GenProduction/python/
scram b -j 1
eval `scram runtime -sh`
cd -

tar xvaf ${BASEDIR}/inputs/${TARBALL}

sed -i 's/exit 0//g' runcmsgrid.sh

ls -lhrt

RANDOMSEED=`od -vAn -N4 -tu4 < /dev/urandom`

#Sometimes the RANDOMSEED is too long for madgraph
RANDOMSEED=`echo $RANDOMSEED | rev | cut -c 3- | rev`

#Run
. runcmsgrid.sh 500 ${RANDOMSEED} 1

outfilename_tmp="$PROCESS"'_'"$RANDOMSEED"
outfilename="${outfilename_tmp//[[:space:]]/}"

mv cmsgrid_final.lhe ${outfilename}.lhe

ls -lhrt
#
#############
#############
# Generate GEN-SIM
echo "1.) GENERATING GEN-SIM"
cmsDriver.py Configuration/GenProduction/python/${HADRONIZER} \
    --filein file:${outfilename}.lhe --fileout file:${outfilename}_gensim.root \
    --mc \
    --step GEN,SIM \
    --eventcontent RAWSIM \
    --datatier GEN-SIM \
    --conditions MCRUN2_71_V1::All \
    --beamspot Realistic50ns13TeVCollision \
    --customise SLHCUpgradeSimulations/Configuration/postLS1Customs.customisePostLS1,Configuration/DataProcessing/Utils.addMonitoring \
    --magField 38T_PostLS1 \
    --python_filename ${outfilename}_gensim.py \
    --no_exec -n ${nevent}

#Make each file unique to make later publication possible
linenumber=`grep -n 'process.source' ${outfilename}_gensim.py | awk '{print $1}'`
linenumber=${linenumber%:*}
total_linenumber=`cat ${outfilename}_gensim.py | wc -l`
bottom_linenumber=$((total_linenumber - $linenumber ))
tail -n $bottom_linenumber ${outfilename}_gensim.py > tail.py
head -n $linenumber ${outfilename}_gensim.py > head.py
echo "    firstRun = cms.untracked.uint32(1)," >> head.py
echo "    firstLuminosityBlock = cms.untracked.uint32($RANDOMSEED)," >> head.py
cat tail.py >> head.py
mv head.py ${outfilename}_gensim.py
rm -rf tail.py

echo "HERE"
ls -trlh

cat ${outfilename}_gensim.py

#Run
cmsRun ${outfilename}_gensim.py

#
############
############
# Generate AOD
export SCRAM_ARCH=slc6_amd64_gcc530
if [ -r CMSSW_8_0_21/src ] ; then 
    echo release CMSSW_8_0_21 already exists
else
    scram p CMSSW CMSSW_8_0_21
fi
cd CMSSW_8_0_21/src
eval `scram runtime -sh`
scram b -j 1
cd -

#cp ${BASEDIR}/inputs/pu_files.py .
#cp ${BASEDIR}/inputs/aod_template.py .

#sed -i 's/XX-GENSIM-XX/'${outfilename}'/g' aod_template.py
#sed -i 's/XX-AODFILE-XX/'${outfilename}'/g' aod_template.py

#mv aod_template.py ${outfilename}_1_cfg.py

#cmsRun ${outfilename}_1_cfg.py
echo "1.) GENERATING AOD"
cmsDriver.py step1 \
    --filein file:${outfilename}_gensim.root --fileout file:${outfilename}_step1.root  \
    --mc \
    --step DIGIPREMIX_S2,DATAMIX,L1,DIGI2RAW,HLT:@frozen2016 \
    --eventcontent PREMIXRAW \
    --datatier GEN-SIM-RAW \
    --conditions 80X_mcRun2_asymptotic_2016_TrancheIV_v6 \
    --era Run2_2016 \
    --nThreads 1 \
    --python_filename ${outfilename}_1_cfg.py \
    --datamix PreMix \
    --pileup_input "dbs:/Neutrino_E-10_gun/RunIISpring15PrePremix-PUMoriond17_80X_mcRun2_asymptotic_2016_TrancheIV_v2-v2/GEN-SIM-DIGI-RAW" \
    --customise Configuration/DataProcessing/Utils.addMonitoring \
    --no_exec -n ${nevent}

cmsRun ${outfilename}_1_cfg.py

echo "2.) GENERATING AOD"
cmsDriver.py step2 \
    --filein file:${outfilename}_step1.root --fileout file:${outfilename}_aod.root \
    --mc \
    --step RAW2DIGI,RECO,EI \
    --eventcontent AODSIM \
    --datatier AODSIM \
    --conditions 80X_mcRun2_asymptotic_2016_TrancheIV_v6 \
    --era Run2_2016 \
    --nThreads 1 \
    --python_filename ${outfilename}_2_cfg.py \
    --customise Configuration/DataProcessing/Utils.addMonitoring \
    --runUnscheduled \
    --no_exec -n ${nevent}

#Run
cmsRun ${outfilename}_2_cfg.py

#
###########
###########
# Generate MiniAODv3
export SCRAM_ARCH=slc6_amd64_gcc630
source /cvmfs/cms.cern.ch/cmsset_default.sh
if [ -r CMSSW_9_4_9/src ] ; then 
    echo release CMSSW_9_4_9 already exists
else
    scram p CMSSW CMSSW_9_4_9
fi
cd CMSSW_9_4_9/src
eval `scram runtime -sh`
scram b -j 1

#scram p CMSSW_9_4_0
#cd CMSSW_9_4_0/src
#eval `scram runtime -sh`
cd -

echo "3.) Generating MINIAOD"
cmsDriver.py step1 \
    --filein file:${outfilename}_aod.root --fileout file:${outfilename}_miniaod.root \
    --mc \
    --step PAT \
    --eventcontent MINIAODSIM \
    --datatier MINIAODSIM \
    --conditions 94X_mcRun2_asymptotic_v3 \
    --era Run2_2016,run2_miniAOD_80XLegacy \
    --nThreads 1 \
    --python_filename ${outfilename}_miniaod_cfg.py \
    --customise Configuration/DataProcessing/Utils.addMonitoring \
    --runUnscheduled \
    --no_exec -n ${nevent}

#Run
cmsRun ${outfilename}_miniaod_cfg.py

#
###########
###########
# Generate NanoAOD
echo "4.) Generating NANOAOD"
export SCRAM_ARCH=slc6_amd64_gcc700
#scram p CMSSW CMSSW 10_2_10
#cd CMSSW 10_2_10/src
#git cms-merge-topic cms-nanoAOD:master-102X
#git checkout -b nanoAOD cms-nanoAOD/master-102X
#scram b -j 2
#eval `scram runtime -sh`
source /cvmfs/cms.cern.ch/cmsset_default.sh
if [ -r CMSSW_10_2_11/src ] ; then 
    echo release CMSSW_10_2_11 already exists
else
    scram p CMSSW CMSSW_10_2_11
fi
cd CMSSW_10_2_11/src
eval `scram runtime -sh`
scram b -j 1
cd -

#https://github.com/CoffeaTeam/CoffeaHarvester/blob/master/crab/mc_NANO_2016.py
cmsDriver.py step1 \
    --filein file:${outfilename}_miniaod.root --fileout file:${outfilename}_nanooad.root \
    --mc \
    --step NANO \
    --eventcontent NANOAODSIM \
    --datatier NANOAODSIM \
    --conditions 102X_mcRun2_asymptotic_v6 \
    --era Run2_2016,run2_nanoAOD_94X2016 \
    --nThreads 1 \
    --python_filename ${outfilename}_nanoaod_cfg.py \
    --customise_commands="process.add_(cms.Service('InitRootHandlers', EnableIMT = cms.untracked.bool(False)))" \
    --customise_commands 'process.particleLevelSequence.remove(process.genParticles2HepMCHiggsVtx);process.particleLevelSequence.remove(process.rivetProducerHTXS);process.particleLevelTables.remove(process.HTXSCategoryTable)' \
    --no_exec -n ${nevent}

#Run
cmsRun ${outfilename}_nanoaod_cfg.py

#
###########
###########
# Stage out

#v1
tar xf $BASEDIR/inputs/copy.tar

# define base output location
#REMOTE_USER_DIR=""

ls -lrht

xrdcp file:///$PWD/${outfilename}_nanooad.root root://cmseos.fnal.gov//store/user/shoh/nanoaod/${PROCESS}/${outfilename}_nanoaod.root
#lcg-cp -v -D srmv2 -b file:///$PWD/${outfilename}_miniaod.root srm://t2-srm-02.lnl.infn.it:8443/srm/managerv2?SFN=/pnfs/lnl.infn.it/data/cms/store/user/shoh/privateSignal/${outfilename}_miniaod.root

#xrdcp file:///$PWD/${outfilename}_miniaod.root root://cmseos.fnal.gov/${REMOTE_USER_DIR}/${outfilename}_miniaod.root
#xrdcp file:///$PWD/${outfilename}_miniaod.root root://cmseos.fnal.gov/${EOSOUTPUT}/${PROCESS}/${outfilename}_miniaod.root
#xrdcp file:///$PWD/${outfilename}_miniaod.root root://cmseos.fnal.gov//store/user/lpcmetx/miniaod/DarkHiggsModel/BBbarDM_90/${PROCESS}/${outfilename}_miniaod.root
#xrdcp file:///$PWD/${outfilename}_miniaod.root root://cmseos.fnal.gov//store/user/shoh/miniaod/BBbarDM_70/${PROCESS}/${outfilename}_miniaod.root
#xrdcp file:///$PWD/${outfilename}_miniaod.root root://cmseos.fnal.gov//store/user/lpcmetx/miniaod/DarkHiggsModel/DiJetsDM/${PROCESS}/${outfilename}_miniaod.root
#if which gfal-copy
#then
#    gfal-copy ${outfilename}_miniaod.root gsiftp://se01.cmsaf.mit.edu:2811/cms/store${REMOTE_USER_DIR}/${outfilename}_miniaod.root
#elif which lcg-cp
#then
#    lcg-cp -v -D srmv2 -b file://$PWD/${outfilename}_miniaod.root gsiftp://se01.cmsaf.mit.edu:2811/cms/store${REMOTE_USER_DIR}/${outfilename}_miniaod.root
#else
    #echo "No way to copy something."                                                                                                                                         
#    exit 1
#fi

echo "DONE."
