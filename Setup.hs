import           Control.Monad                      (void, when)
import           Data.List                          (isSuffixOf)
import           Distribution.PackageDescription    (HookedBuildInfo, PackageDescription (testSuites), TestSuite (..))
import           Distribution.Simple
import           Distribution.Simple.LocalBuildInfo (ComponentName (..), LocalBuildInfo (..))
import           Distribution.Simple.Setup          (BuildFlags (..), fromFlag)
import           Distribution.Simple.Utils
import           Distribution.Verbosity             (Verbosity)
import           System.Environment                 (getEnv, getEnvironment, setEnv)

buildingInCabal :: IO Bool
buildingInCabal = do
  parentProcess <- getEnv "_"
  return $ not ("stack" `isSuffixOf` parentProcess)

-- note: this only works in cabal, stack doesn't seem to pass these?
willBuildLiveSuite :: PackageDescription  -> Bool
willBuildLiveSuite = any isLiveTest . testSuites
  where isLiveTest t = testName t == "live" && testEnabled t

main :: IO ()
main = defaultMainWithHooks simpleUserHooks
         { buildHook = myBuildHook
         }

setupLiveTests :: Verbosity -> IO ()
setupLiveTests v = do
    putStrLn "Running truffle deploy and convertAbi before building tests"
    rawCommand v "truffle" ["deploy"] Nothing
    rawCommand v "./test-support/convertAbi.sh" [] Nothing
    rawCommand v "./test-support/inject-contract-addresses.sh" [] (Just [("EXPORT_STORE", exportStore)])

rawCommand :: Verbosity -> String -> [String] -> Maybe [(String, String)] -> IO ()
rawCommand v prog args moreEnv = do
    env <- getEnvironment
    let allEnvs = case moreEnv of
                    Nothing   -> env
                    Just more -> more ++ env
    maybeExit $ rawSystemIOWithEnv v prog args Nothing (Just allEnvs) Nothing Nothing Nothing

exportStore :: String
exportStore = ".detected-contract-addresses"

myBuildHook :: PackageDescription -> LocalBuildInfo -> UserHooks -> BuildFlags -> IO ()
myBuildHook pd lbi uh flags = do
    inCabal <- buildingInCabal
    let v = fromFlag $ buildVerbosity flags
        args = buildArgs flags
        isStackTest = not inCabal && "test:live" `elem` args
        isCabalTest = inCabal && willBuildLiveSuite pd && (null args || "live" `elem` args)
        hasLiveTestTarget = isStackTest || isCabalTest
    when hasLiveTestTarget $ setupLiveTests v
    buildHook simpleUserHooks pd lbi uh flags
