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

export nevent="10"

# output
export EOSOUTPUT=${eos_output}

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

export SCRAM_ARCH=slc6_amd64_gcc481
CMSSWRELEASE=CMSSW_7_1_20_patch3
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
cmsDriver.py Configuration/GenProduction/python/${HADRONIZER} --filein file:${outfilename}.lhe --fileout file:${outfilename}_gensim.root --mc --eventcontent RAWSIM --customise SLHCUpgradeSimulations/Configuration/postLS1Customs.customisePostLS1,Configuration/DataProcessing/Utils.addMonitoring --datatier GEN-SIM --conditions MCRUN2_71_V1::All --beamspot Realistic50ns13TeVCollision --step GEN,SIM --magField 38T_PostLS1 --python_filename ${outfilename}_gensim.py --no_exec -n ${nevent}

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

#Run
cmsRun ${outfilename}_gensim.py

#
############
############
# Generate AOD

export SCRAM_ARCH=slc6_amd64_gcc530
scram p CMSSW CMSSW_8_0_21
cd CMSSW_8_0_21/src
eval `scram runtime -sh`
cd -

cp ${BASEDIR}/inputs/pu_files.py .
cp ${BASEDIR}/inputs/aod_template.py .

sed -i 's/XX-GENSIM-XX/'${outfilename}'/g' aod_template.py
sed -i 's/XX-AODFILE-XX/'${outfilename}'/g' aod_template.py

mv aod_template.py ${outfilename}_1_cfg.py

cmsRun ${outfilename}_1_cfg.py
echo "2.) GENERATING AOD"
cmsDriver.py step2 --filein file:${outfilename}_step1.root --fileout file:${outfilename}_aod.root --mc --eventcontent AODSIM --runUnscheduled --datatier AODSIM --conditions 80X_mcRun2_asymptotic_2016_TrancheIV_v6 --step RAW2DIGI,RECO,EI --nThreads 1 --era Run2_2016 --python_filename ${outfilename}_2_cfg.py --no_exec --customise Configuration/DataProcessing/Utils.addMonitoring -n ${nevent}

#Run
cmsRun ${outfilename}_2_cfg.py

#
###########
###########
# Generate MiniAODv2
echo "3.) Generating MINIAOD"
cmsDriver.py step1 --filein file:${outfilename}_aod.root --fileout file:${outfilename}_miniaod.root --mc --eventcontent MINIAODSIM --runUnscheduled --datatier MINIAODSIM --conditions 80X_mcRun2_asymptotic_2016_TrancheIV_v6 --step PAT --nThreads 1 --era Run2_2016 --python_filename ${outfilename}_miniaod_cfg.py --no_exec --customise Configuration/DataProcessing/Utils.addMonitoring -n ${nevent}

#Run
cmsRun ${outfilename}_miniaod_cfg.py

#
###########
###########
# Stage out

#v1
tar xf $BASEDIR/inputs/copy.tar

# define base output location
#REMOTE_USER_DIR=""

ls -lrht

lcg-cp -v -D srmv2 -b file:///$PWD/${outfilename}_miniaod.root srm://t2-srm-02.lnl.infn.it:8443/srm/managerv2?SFN=/pnfs/lnl.infn.it/data/cms/store/user/shoh/privateSignal/${outfilename}_miniaod.root

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
