module Main (main) where

import Api (app, applyArgs, blake2bHash, estimateTxFees, hashScript)
import Data.ByteString.Lazy.Char8 qualified as LC8
import Data.Kind (Type)
import Network.HTTP.Client (defaultManagerSettings, newManager)
import Network.HTTP.Types (Status (Status))
import Network.Wai.Handler.Warp (Port)
import Network.Wai.Handler.Warp qualified as Warp
import Plutus.V1.Ledger.Api qualified as Ledger
import Servant.Client (
  BaseUrl (baseUrlPort),
  ClientEnv,
  ClientError (FailureResponse),
  ClientM,
  ResponseF (Response),
  mkClientEnv,
  parseBaseUrl,
  runClientM,
 )
import System.Exit (die)
import Test.Hspec (
  ActionWith,
  Spec,
  around,
  context,
  describe,
  hspec,
  it,
  runIO,
  shouldBe,
  shouldSatisfy,
 )
import Test.Hspec.Core.Spec (SpecM)
import Types (
  AppliedScript (AppliedScript),
  ApplyArgsRequest (ApplyArgsRequest, args, script),
  Blake2bHash (Blake2bHash),
  BytesToHash (BytesToHash),
  Cbor (Cbor),
  Env,
  Fee (Fee),
  HashScriptRequest (HashScriptRequest),
  HashedScript (HashedScript),
  newEnvIO,
  unsafeDecode,
 )

main :: IO ()
main = hspec serverSpec

serverSpec :: Spec
serverSpec = do
  describe "Api.Handlers.applyArgs" applyArgsSpec
  describe "Api.Handlers.estimateTxFees" feeEstimateSpec
  describe "Api.Handlers.hashScript" hashScriptSpec
  describe "Api.Handlers.blake2bHash" blake2bHashSpec

applyArgsSpec :: Spec
applyArgsSpec = around withTestApp $ do
  clientEnv <- setupClientEnv

  context "POST apply-args" $ do
    it "returns the same script when called without args" $ \port -> do
      result <-
        runClientM' (clientEnv port) $
          applyArgs unappliedRequestFixture
      result `shouldBe` Right (AppliedScript unappliedScriptFixture)

    -- FIXME
    -- See: https://github.com/Plutonomicon/cardano-browser-tx/issues/189
    --
    -- This is returning a different applied script than the test fixtures. The
    -- fixtures were obtained with Plutus using `applyCode` (not `applyArguments`
    -- which the server implementation uses). Need to investigate more
    it "returns the correct partially applied Plutus script" $ \port -> do
      result <-
        runClientM' (clientEnv port) $
          applyArgs partiallyAppliedRequestFixture
      result `shouldBe` Right partiallyAppliedScriptFixture

    -- FIXME
    -- See above
    it "returns the correct fully applied Plutus script" $ \port -> do
      result <-
        runClientM' (clientEnv port) $
          applyArgs fullyAppliedRequestFixture
      result `shouldBe` Right fullyAppliedScriptFixture

feeEstimateSpec :: Spec
feeEstimateSpec = around withTestApp $ do
  clientEnv <- setupClientEnv

  context "GET fees" $ do
    it "estimates the correct fee" $ \port -> do
      result <-
        runClientM' (clientEnv port) $
          estimateTxFees cborTxFixture
      -- This is probably incorrect. See:
      -- https://github.com/Plutonomicon/cardano-browser-tx/issues/123
      result `shouldBe` Right (Fee 168449)

    it "catches invalid hex strings" $ \port -> do
      result <-
        runClientM' (clientEnv port)
          . estimateTxFees
          $ Cbor "deadbeefq"
      result `shouldSatisfy` expectError 400 "invalid bytestring size"

    it "catches invalid CBOR-encoded transactions" $ \port -> do
      result <-
        runClientM' (clientEnv port)
          . estimateTxFees
          $ Cbor "deadbeef"
      result
        `shouldSatisfy` expectError
          400
          "DecoderErrorDeserialiseFailure \"Shelley Tx\" \
          \(DeserialiseFailure 0 \"expected list len or indef\")"
  where
    expectError :: Int -> LC8.ByteString -> Either ClientError Fee -> Bool
    expectError code body = \case
      Left (FailureResponse _ (Response (Status scode _) _ _ sbody))
        | scode == code && sbody == body -> True
      _ -> False

hashScriptSpec :: Spec
hashScriptSpec = around withTestApp $ do
  clientEnv <- setupClientEnv

  context "POST hash-script" $ do
    it "hashes the script" $ \port -> do
      result <-
        runClientM' (clientEnv port) $
          hashScript hashScriptRequestFixture
      result `shouldBe` Right hashedScriptFixture

blake2bHashSpec :: Spec
blake2bHashSpec = around withTestApp $ do
  clientEnv <- setupClientEnv

  context "POST blake2b" $ do
    it "gets the blake2b_256 hash" $ \port -> do
      result <-
        runClientM' (clientEnv port) $
          blake2bHash (BytesToHash "foo")
      result `shouldBe` Right blake2bRes
  where
    -- obtained from `fromBuiltin . blake2b_256 $ toBuiltin @ByteString "foo"`
    blake2bRes :: Blake2bHash
    blake2bRes =
      Blake2bHash
        "\184\254\159\DELbU\166\250\b\246h\171c*\141\b\SUB\216y\131\199|\210t\228\140\228P\240\179I\253"

setupClientEnv :: SpecM Port (Port -> ClientEnv)
setupClientEnv = do
  baseUrl <- runIO $ parseBaseUrl "http://localhost"
  manager <- runIO $ newManager defaultManagerSettings
  pure $
    let clientEnv port = mkClientEnv manager $ baseUrl {baseUrlPort = port}
     in clientEnv

withTestApp :: ActionWith (Port -> IO ())
withTestApp = Warp.testWithApplication $ app <$> newEnvIO'
  where
    newEnvIO' :: IO Env
    newEnvIO' = either die pure =<< newEnvIO

runClientM' ::
  forall (a :: Type).
  ClientEnv ->
  ClientM a ->
  IO (Either ClientError a)
runClientM' = flip runClientM

-- This is a known-good 'Tx AlonzoEra'
cborTxFixture :: Cbor
cborTxFixture =
  Cbor $
    mconcat
      [ "84a500818258205d677265fa5bb21ce6d8c7502aca70b9316d10e958611f3c6b758f65a"
      , "d959996000d818258205d677265fa5bb21ce6d8c7502aca70b9316d10e958611f3c6b75"
      , "8f65ad95999600018282581d600f45aaf1b2959db6e5ff94dbb1f823bf257680c3c723a"
      , "c2d49f975461a0023e8fa82581d60981fc565bcf0c95c0cfa6ee6693875b60d529d87ed"
      , "7082e9bf03c6a41a000f4240021a0002b5690e81581c0f45aaf1b2959db6e5ff94dbb1f"
      , "823bf257680c3c723ac2d49f97546a10081825820096092b8515d75c2a2f75d6aa7c519"
      , "1996755840e81deaa403dba5b690f091b6584063721fd9360d569968defac287e76cfaa"
      , "767366ecf6709b8354e02e2df6c35d78453adb04ec76f8a3d1287468b8c244ff051dcd0"
      , "f29dbcac1f7baf3e2d06ce06f5f6"
      ]

hashScriptRequestFixture :: HashScriptRequest
hashScriptRequestFixture =
  HashScriptRequest $
    unsafeDecode "Script" "\"4d01000033222220051200120011\""

hashedScriptFixture :: HashedScript
hashedScriptFixture =
  HashedScript $
    unsafeDecode
      "ScriptHash"
      "{\"getScriptHash\":\
      \\"67f33146617a5e61936081db3b2117cbf59bd2123748f58ac9678656\"}"

unappliedRequestFixture :: ApplyArgsRequest
unappliedRequestFixture =
  ApplyArgsRequest
    { script = unappliedScriptFixture
    , args = []
    }

partiallyAppliedRequestFixture :: ApplyArgsRequest
partiallyAppliedRequestFixture = unappliedRequestFixture {args = [Ledger.B ""]}

fullyAppliedRequestFixture :: ApplyArgsRequest
fullyAppliedRequestFixture =
  unappliedRequestFixture
    { args =
        [ Ledger.B ""
        , Ledger.B ""
        , Ledger.B ""
        , Ledger.I 0
        , Ledger.B ""
        , Ledger.I 0
        ]
    }

-- A minting policy without any arguments applied
unappliedScriptFixture :: Ledger.Script
unappliedScriptFixture =
  unsafeDecode
    "Script"
    $ mconcat
      [ "\""
      , "590a9a01000032333222323232323233223233223232333222333222333222"
      , "33223233322232323322323233223233333222223322333332222233223322"
      , "33223232323232222222223235300f00222353013002222232222222333353"
      , "02901023232323232300100e3200135505a2253353503e0011533530593335"
      , "303d12001051500332635302e3357389210b756e726561636861626c650002"
      , "f01f150051500422135355054002225335305d333573466e3c009406417c17"
      , "854cd4c174ccd4c10448004155401c00454024540204c01800c4cd40f0cd54"
      , "140c0d4010cdc0a40009001281e8a99a982a99ab9c4901124e4654206d7573"
      , "74206265206275726e6564000561500110561533530543301b00f353035002"
      , "2220011500115335305433573892011f4f776e6572206d757374207369676e"
      , "20746865207472616e73616374696f6e000551500110551533530533335530"
      , "1c120013502f50482353022001222533530573303f00333041304901a50431"
      , "0581333573466e1cccc07000806cd4c0e001488800d200205905800b105513"
      , "357389211f556e6465726c79696e67204e4654206d75737420626520756e6c"
      , "6f636b656400054232323232323225335305a33300f00835303b0082220020"
      , "011500215335305a33573892013e45786163746c79206f6e65206e65772074"
      , "6f6b656e206d757374206265206d696e74656420616e642065786163746c79"
      , "206f6e65206f6c64206275726e740005b15002105b15335305833004500233"
      , "042304a018504415335305833004500133042304b01a504415335305833355"
      , "30211200135034504d3300533042304b35303900622200150443370266e054"
      , "00cc1514004c151400804041685415854158541584cdc199b8250020184828"
      , "270044cdc199b8250010154828270044d4c0d800c888008894cd4c158ccd5c"
      , "d19b880020530580571058133355301f1200135032504b3300300100200e22"
      , "23530240012225335305933041006003153353059333573466e1c014ccc078"
      , "0080e40e416c16854cd4d4110004854cd4d4114d4c09805488888888894cd4"
      , "d413cccd54c0b44800540b08d4d54178004894cd4c19cccd5cd19b8f00200e"
      , "0690681350540031505300221350523535505e001220011505021323335734"
      , "66ebc008004178174c8d4d5415400488cdd2a400066ae80dd480119aba0375"
      , "20026ec4090cd54155405cc0e8024416c4168416841688c894cd4c154ccc02"
      , "800c004d4c0d800c8880045400854cd4c154cd5ce2493e45786163746c7920"
      , "6f6e65206e657720746f6b656e206d757374206265206d696e74656420616e"
      , "642065786163746c79206f6e65206f6c64206275726e740005615002105615"
      , "33530533301a00e353034001222001105513357389211f4f776e6572206d75"
      , "7374207369676e20746865207472616e73616374696f6e0005423232323230"
      , "0100d320013550592253353503d001153353503d32635302d3357389210b75"
      , "6e726561636861626c650002e01e150042213300500200122135355053002"
      , "225335305c333573466e3c009406017817454cd4d410400454020884cc0240"
      , "080044c01800c88d4d54140008894cd4d40f800c54cd4c164ccd5cd19b8f00"
      , "2303800705b05a153353059333573466e1c005200205b05a15006150051500"
      , "5221500715335305433573892011e45786163746c79206f6e65204e4654206"
      , "d757374206265206d696e7465640005515001105515335305333355301c120"
      , "013502f50482353022001222533530573303f00333041304901a5043133357"
      , "3466e1cccc07000806cd4c0e001488800d2002059058105800b10551335738"
      , "9211d556e6465726c79696e67204e4654206d757374206265206c6f636b656"
      , "4000542322232323001007320013550532253353503700110532213535504d"
      , "0022253353056333573466e3c009404816015c54cd4d40ec004415c884d4d5"
      , "4144008894cd4d40fc00c416c884d4d5415400888c94cd4d411001054cd4c1"
      , "7cccd5cd19b8f007501306106015335305f333573466e3c00d404018418054"
      , "cd4c17cccd5cd19b87006480041841804ccd5cd19b87002480081841804180"
      , "540045400488418854cd4c178ccd5cd19b8f002501206005f15335305e3335"
      , "73466e3c019403c18017c54cd4c178ccd5cd19b870014800418017c4ccd5cd"
      , "19b870054800818017c417c417c417c4c01800c4c0b8d4c0c0010888ccc0d0"
      , "00c0140104c0ac0044d4c03800488cccd4c0580048c98d4c070cd5ce249024"
      , "c680001d00d2001232635301c3357389201024c680001d00d232635301c335"
      , "7389201024c680001d00d22232323001005320013550422233535026001480"
      , "0088d4d540f0008894cd4c114ccd5cd19b8f00200904704613007001130060"
      , "033200135504122335350250014800088d4d540ec008894cd4c110ccd5cd19"
      , "b8f00200704604510011300600349888d4c01c00888888888894cd4d40c0cc"
      , "d54c03848005403494cd4c118ccd5cd19b8f00c00104804713503300115032"
      , "00321048104613350162253353502500221003100150243200135503a22112"
      , "22533535021001135350190032200122133353501b00522002300400233355"
      , "30071200100500400122123300100300220012222222222123333333333001"
      , "00b00a00900800700600500400300220012221233300100400300220012122"
      , "22300400521222230030052122223002005212222300100520011200120012"
      , "12222300400522122223300300600522122223300200600521222230010052"
      , "001123350032233353501d00322002002001353501b0012200112212330010"
      , "030021200123724666aa600a24002e28008cc88cc008c8dc9198120008029a"
      , "9802801911001198011b923530050032220013300237246a600a0064440060"
      , "02a010a0129110022212333001004003002200132001355020221122253353"
      , "5007001100222133005002333553007120010050040013200135501f221222"
      , "53353500600215335350060011023221024221533535008003102422153353"
      , "02533007004002133353009120010070030011026112200212212233001004"
      , "00312001223530030022235300500322323353010005233530110042533530"
      , "21333573466e3c00800408c0885400c408880888cd4c044010808894cd4c08"
      , "4ccd5cd19b8f00200102302215003102215335350090032153353500a00221"
      , "335300e0022335300f00223353013002233530140022330180020012025233"
      , "53014002202523301800200122202522233530110042025222533530263335"
      , "73466e1c01800c0a009c54cd4c098ccd5cd19b870050020280271330210040"
      , "01102710271020153353500900121020102022123300100300220011212230"
      , "02003112200112001212230020032221223330010050040032001212230020"
      , "0321223001003200122333573466e3c00800404003c4cd4008894cd4c03400"
      , "8403c400403048848cc00400c0084800488d4d5400c00888d4d5401400c894"
      , "cd4c038ccd5cd19b8f00400201000f133009003001100f1122123300100300"
      , "211200122333573466e1c00800402402094cd4c014ccd5cd19b88001002007"
      , "0061480004005208092f401133573892113526f79616c6974696573206e6f7"
      , "42070616964000033200135500422253353004333573466e20009208004006"
      , "00513371600400226600666e0c0092080043371666e1800920800400112200"
      , "21220012001112323001001223300330020020011"
      , "\""
      ]

partiallyAppliedScriptFixture :: AppliedScript
partiallyAppliedScriptFixture =
  AppliedScript
    . unsafeDecode
      "Script"
    $ mconcat
      [ "\""
      , "590a9e0100003323332223232323232332232332232323332223332223332223322323"
      , "3322232323322323233223233333222223322333332222233223322332232323232322"
      , "22222223235300f0022235301300222223222222233335302901023232323232300100"
      , "e3200135505a2253353503e0011533530593335303d12001051500332635302e335738"
      , "92010b756e726561636861626c650002f01f150051500422135355054002225335305d"
      , "333573466e3c009406417c17854cd4c174ccd4c10448004155401c00454024540204c0"
      , "1800c4cd40f0cd54140c0d4010cdc0a40009001281e8a99a982a99ab9c4901124e4654"
      , "206d757374206265206275726e6564000561500110561533530543301b00f353035002"
      , "2220011500115335305433573892011f4f776e6572206d757374207369676e20746865"
      , "207472616e73616374696f6e0005515001105515335305333355301c120013502f5048"
      , "2353022001222533530573303f00333041304901a504310581333573466e1cccc07000"
      , "806cd4c0e001488800d200205905800b105513357389211f556e6465726c79696e6720"
      , "4e4654206d75737420626520756e6c6f636b656400054232323232323225335305a333"
      , "00f00835303b0082220020011500215335305a33573892013e45786163746c79206f6e"
      , "65206e657720746f6b656e206d757374206265206d696e74656420616e642065786163"
      , "746c79206f6e65206f6c64206275726e740005b15002105b1533530583300450023304"
      , "2304a018504415335305833004500133042304b01a5044153353058333553021120013"
      , "5034504d3300533042304b35303900622200150443370266e05400cc1514004c151400"
      , "804041685415854158541584cdc199b8250020184828270044cdc199b8250010154828"
      , "270044d4c0d800c888008894cd4c158ccd5cd19b880020530580571058133355301f12"
      , "00135032504b3300300100200e22235302400122253353059330410060031533530593"
      , "33573466e1c014ccc0780080e40e416c16854cd4d4110004854cd4d4114d4c09805488"
      , "888888894cd4d413cccd54c0b44800540b08d4d54178004894cd4c19cccd5cd19b8f00"
      , "200e0690681350540031505300221350523535505e00122001150502132333573466eb"
      , "c008004178174c8d4d5415400488cdd2a400066ae80dd480119aba037520026ec4090c"
      , "d54155405cc0e8024416c4168416841688c894cd4c154ccc02800c004d4c0d800c8880"
      , "045400854cd4c154cd5ce2493e45786163746c79206f6e65206e657720746f6b656e20"
      , "6d757374206265206d696e74656420616e642065786163746c79206f6e65206f6c6420"
      , "6275726e74000561500210561533530533301a00e35303400122200110551335738921"
      , "1f4f776e6572206d757374207369676e20746865207472616e73616374696f6e000542"
      , "32323232300100d320013550592253353503d001153353503d32635302d3357389210b"
      , "756e726561636861626c650002e01e1500422133005002001221353550530022253353"
      , "05c333573466e3c009406017817454cd4d410400454020884cc0240080044c01800c88"
      , "d4d54140008894cd4d40f800c54cd4c164ccd5cd19b8f002303800705b05a153353059"
      , "333573466e1c005200205b05a150061500515005221500715335305433573892011e45"
      , "786163746c79206f6e65204e4654206d757374206265206d696e746564000551500110"
      , "5515335305333355301c120013502f50482353022001222533530573303f0033304130"
      , "4901a50431333573466e1cccc07000806cd4c0e001488800d2002059058105800b1055"
      , "13357389211d556e6465726c79696e67204e4654206d757374206265206c6f636b6564"
      , "000542322232323001007320013550532253353503700110532213535504d002225335"
      , "3056333573466e3c009404816015c54cd4d40ec004415c884d4d54144008894cd4d40f"
      , "c00c416c884d4d5415400888c94cd4d411001054cd4c17cccd5cd19b8f007501306106"
      , "015335305f333573466e3c00d404018418054cd4c17cccd5cd19b87006480041841804"
      , "ccd5cd19b87002480081841804180540045400488418854cd4c178ccd5cd19b8f00250"
      , "1206005f15335305e333573466e3c019403c18017c54cd4c178ccd5cd19b8700148004"
      , "18017c4ccd5cd19b870054800818017c417c417c417c4c01800c4c0b8d4c0c0010888c"
      , "cc0d000c0140104c0ac0044d4c03800488cccd4c0580048c98d4c070cd5ce249024c68"
      , "0001d00d2001232635301c3357389201024c680001d00d232635301c3357389201024c"
      , "680001d00d222323230010053200135504222335350260014800088d4d540f0008894c"
      , "d4c114ccd5cd19b8f00200904704613007001130060033200135504122335350250014"
      , "800088d4d540ec008894cd4c110ccd5cd19b8f00200704604510011300600349888d4c"
      , "01c00888888888894cd4d40c0ccd54c03848005403494cd4c118ccd5cd19b8f00c0010"
      , "4804713503300115032003210481046133501622533535025002210031001502432001"
      , "35503a2211222533535021001135350190032200122133353501b00522002300400233"
      , "3553007120010050040012212330010030022001222222222212333333333300100b00"
      , "a009008007006005004003002200122212333001004003002200121222230040052122"
      , "2230030052122223002005212222300100520011200120012122223004005221222233"
      , "00300600522122223300200600521222230010052001123350032233353501d0032200"
      , "2002001353501b0012200112212330010030021200123724666aa600a24002e28008cc"
      , "88cc008c8dc9198120008029a9802801911001198011b9235300500322200133002372"
      , "46a600a006444006002a010a0129110022212333001004003002200132001355020221"
      , "1222533535007001100222133005002333553007120010050040013200135501f22122"
      , "2533535006002153353500600110232210242215335350080031024221533530253300"
      , "7004002133353009120010070030011026112200212212233001004003120012235300"
      , "3002223530050032232335301000523353011004253353021333573466e3c00800408c"
      , "0885400c408880888cd4c044010808894cd4c084ccd5cd19b8f0020010230221500310"
      , "2215335350090032153353500a00221335300e0022335300f002233530130022335301"
      , "4002233018002001202523353014002202523301800200122202522233530110042025"
      , "22253353026333573466e1c01800c0a009c54cd4c098ccd5cd19b87005002028027133"
      , "0210040011027102710201533535009001210201020221233001003002200112122300"
      , "2003112200112001212230020032221223330010050040032001212230020032122300"
      , "1003200122333573466e3c00800404003c4cd4008894cd4c034008403c400403048848"
      , "cc00400c0084800488d4d5400c00888d4d5401400c894cd4c038ccd5cd19b8f0040020"
      , "1000f133009003001100f1122123300100300211200122333573466e1c008004024020"
      , "94cd4c014ccd5cd19b880010020070061480004005208092f401133573892113526f79"
      , "616c6974696573206e6f742070616964000033200135500422253353004333573466e2"
      , "000920800400600513371600400226600666e0c0092080043371666e18009208004001"
      , "1220021220012001112323001001223300330020020014890001"
      , "\""
      ]

fullyAppliedScriptFixture :: AppliedScript
fullyAppliedScriptFixture =
  AppliedScript
    . unsafeDecode
      "Script"
    $ mconcat
      [ "\""
      , "5912f9010000333333323233322232323232332232332232323322323232333222333"
      , "222333222332232333222323232323322323333322222323233333333222222223333"
      , "222233223322332233223322332233223322323232323232323232323232323232333"
      , "33222223322222222232323232232325335306e33223232323232323235302e353018"
      , "008220022222222222323333530570142533530830153353083013335306312001223"
      , "535504200222353550440032253353089013307a004002133079003001108a0133506"
      , "533550413060001337021000290012833299a9a83518078011080089931a983d19ab9"
      , "c49010b756e726561636861626c650007b0791085011335738921124e4654206d7573"
      , "74206265206275726e6564000840115335308301533530830133039501135307d0012"
      , "2200110850113357389211f4f776e6572206d757374207369676e2074686520747261"
      , "6e73616374696f6e000840115335308301333553057120013505d5075253353084015"
      , "3353084013306835303f0012220033306a3072023506c1085011086011333573466e1"
      , "cccc0e4d4c0fc004888008090d4c1f800888800d2002086010850110850135303a501"
      , "12222222222009108501133573892011f556e6465726c79696e67204e4654206d7573"
      , "7420626520756e6c6f636b65640008401108401108401232323232322533530890153"
      , "3530890133301300735308301007222002001108b0113357389213e45786163746c79"
      , "206f6e65206e657720746f6b656e206d757374206265206d696e74656420616e64206"
      , "5786163746c79206f6e65206f6c64206275726e740008a01153353089015335308901"
      , "3300550033306f30770255071153353089013300550023306f3078027507113335530"
      , "5d1200135063507b330063306f30783530830100722200150713370266e054010c220"
      , "054008c22005400d4058422804422804422c044cd5ce248113526f79616c697469657"
      , "3206e6f7420706169640008a01108a0113370666e09400809120a09c0113370666e09"
      , "400408520a09c01135307f003222002225335308601333573466e2000822404220042"
      , "1c044220044ccd54c16848004d418141e0cc00c004009404c888d4c1040048894cd4c"
      , "22404cc1b401800c54cd4c22404ccd5cd19b8700533303e00206706708b0108a01153"
      , "35350705335350700012132353042001222222222253353507c333553069120015068"
      , "235355053001225335309801333573466e3c00803c26804264044d42040400c542000"
      , "400884d41fcd4d5414c00488004541f54060541c484c8ccd5cd19baf00200108d0108"
      , "c013235355048001223374a900019aba0375200466ae80dd48009bb10830133550485"
      , "01a3067008108a01108a01108a01225335308401533530840133300e00200135307e0"
      , "0222200110860113357389213e45786163746c79206f6e65206e657720746f6b656e2"
      , "06d757374206265206d696e74656420616e642065786163746c79206f6e65206f6c64"
      , "206275726e740008501153353084013303a501235307e002222001108601133573892"
      , "11f4f776e6572206d757374207369676e20746865207472616e73616374696f6e0008"
      , "50110850125335308301533530830153353506453353506a301200221001132635307"
      , "a33573892010b756e726561636861626c650007b07910840122135355042002225335"
      , "3506800315335308701333573466e3c008c19001422404220044ccd5cd19b87001480"
      , "082240422004422004884228044214044cd5ce2491e45786163746c79206f6e65204e"
      , "4654206d757374206265206d696e74656400084011533530830133355305712001350"
      , "5d5075253353084013306835303f0012220033306a3072023506c1333573466e1cccc"
      , "0e4d4c0fc004888008090d4c1f800888800d2002086010850110850135303a5011222"
      , "2222222009108501133573892011d556e6465726c79696e67204e4654206d75737420"
      , "6265206c6f636b65640008401108401353038500f2222222222007232223253353506"
      , "25335350623006353032500922222222220072135065001150632153353505d001107"
      , "d2213535503b002225335350610031081012213535503f00222533535065003153353"
      , "08401533530840133075006500d133075002500a10850115335308401333573466e1c"
      , "015200108601085011333573466e1c005200208601085011085011533530840153353"
      , "0840133075002500d133075006500a10850115335308401333573466e1c0052001086"
      , "01085011333573466e1c0152002086010850110850110850122108701107c13057353"
      , "0740042223330780030050041305400132001355079225335350580011505f2213535"
      , "5036002225335307b3306c002500b1350640011300600332001355078225335350570"
      , "011505e22135355035002225335307a3306b002500a13506300113006003135302a50"
      , "01222222222200913530130032200232001355075225335350540011505b221353550"
      , "320022253353077330680025007135060001130060031353011001223333530150012"
      , "32635306a335738921024c680006b0692001232635306a3357389201024c680006b06"
      , "9232635306a3357389201024c680006b0693333573466e1d401120062304830643574"
      , "26aae7940208cccd5cd19b875005480108cc120c194d5d0a8039bae357426ae89401c"
      , "8cccd5cd19b875006480088cc120c198d5d0a80498369aba135744a01246666ae68cd"
      , "c3a803a40004609060ce6ae84d55cf280591931a983499ab9c06b06a0680670660650"
      , "643333573466e1cd55cea8012400046602264646464646464646464646666ae68cdc3"
      , "9aab9d500a480008cccccccccc0cccd408c8c8c8cccd5cd19b8735573aa0049000119"
      , "81c98161aba150023028357426ae8940088c98d4c1d8cd5ce03c03b83a83a09aab9e5"
      , "001137540026ae854028cd408c090d5d0a804999aa8133ae502535742a010666aa04c"
      , "eb94094d5d0a80399a8118161aba15006335023335502f02d75a6ae854014c8c8c8cc"
      , "cd5cd19b8735573aa0049000119a8209919191999ab9a3370e6aae754009200023350"
      , "4933503275a6ae854008c0ccd5d09aba25002232635307a3357380f80f60f20f026aa"
      , "e7940044dd50009aba150023232323333573466e1cd55cea80124000466a08e66a064"
      , "eb4d5d0a80118199aba135744a004464c6a60f466ae701f01ec1e41e04d55cf280089"
      , "baa001357426ae8940088c98d4c1d8cd5ce03c03b83a83a09aab9e5001137540026ae"
      , "854010cd408dd71aba15003335023335502f75c40026ae854008c0a4d5d09aba25002"
      , "23263530723357380e80e60e20e026ae8940044d5d1280089aba25001135744a00226"
      , "ae8940044d5d1280089aba25001135744a00226aae7940044dd50009aba1500232323"
      , "23333573466e1d400520062301a3024357426aae79400c8cccd5cd19b875002480108"
      , "c064c098d5d09aab9e500423333573466e1d400d2002230193022357426aae7940148"
      , "cccd5cd19b875004480008c070dd71aba135573ca00c464c6a60da66ae701bc1b81b0"
      , "1ac1a81a41a04d55cea80089baa001357426ae8940088c98d4c198cd5ce0340338328"
      , "32083309931a983299ab9c49010350543500066064135573ca00226ea80044d55cea8"
      , "0189aab9e5002135573ca00226ea80048848cc00400c0088004848888c01001484888"
      , "8c00c014848888c008014848888c004014800448c88c008dd6000990009aa82e91199"
      , "9aab9f0012503f233503e30043574200460066ae8800814c8c8c8c8cccd5cd19b8735"
      , "573aa0069000119980c1919191999ab9a3370e6aae7540092000233046301335742a0"
      , "0466a0180246ae84d5d1280111931a982b99ab9c059058056055135573ca00226ea80"
      , "04d5d0a801999aa803bae500635742a00466a010eb8d5d09aba250022326353053335"
      , "7380aa0a80a40a226ae8940044d55cf280089baa0011335500175ceb44488c88c008d"
      , "d5800990009aa82d91191999aab9f0022503e233503d3355019300635573aa004600a"
      , "6aae794008c010d5d100182909aba100112232323333573466e1d4005200023504230"
      , "05357426aae79400c8cccd5cd19b87500248008941088c98d4c144cd5ce0298290280"
      , "2782709aab9d500113754002464646666ae68cdc39aab9d5002480008cc05cc014d5d"
      , "0a8011bad357426ae8940088c98d4c138cd5ce02802782682609aab9e500113754002"
      , "4646666ae68cdc39aab9d5001480008dd71aba135573ca004464c6a609866ae701381"
      , "3412c1284dd500089119191999ab9a3370ea00290021280f11999ab9a3370ea004900"
      , "111a81098031aba135573ca00846666ae68cdc3a801a40004a042464c6a609e66ae70"
      , "14414013813413012c4d55cea80089baa0012323333573466e1d40052002205523333"
      , "573466e1d400920002055232635304b33573809a09809409209026aae74dd50009191"
      , "91919191999ab9a3370ea0029006101211999ab9a3370ea0049005101311999ab9a33"
      , "70ea00690041198121bae35742a00a6eb4d5d09aba2500523333573466e1d40112006"
      , "233026375c6ae85401cdd71aba135744a00e46666ae68cdc3a802a400846605660186"
      , "ae854024dd71aba135744a01246666ae68cdc3a803240044605a601a6ae84d55cf280"
      , "591999ab9a3370ea00e90001181618071aba135573ca018464c6a60a666ae70154150"
      , "14814414013c13813413012c4d55cea80209aab9e5003135573ca00426aae7940044d"
      , "d50009191919191999ab9a3370ea0029001119981f9bad35742a0086eb4d5d0a8019b"
      , "ad357426ae89400c8cccd5cd19b875002480008c104c020d5d09aab9e500623263530"
      , "4c33573809c09a09609409226aae75400c4d5d1280089aab9e5001137540024646466"
      , "66ae68cdc3a800a40044607e6eb8d5d09aab9e500323333573466e1d4009200023041"
      , "375c6ae84d55cf280211931a982499ab9c04b04a048047046135573aa00226ea80044"
      , "4888c8c8cccd5cd19b8735573aa0049000119aa80818031aba150023005357426ae89"
      , "40088c98d4c124cd5ce02582502402389aab9e5001137540024446464600200a64002"
      , "6aa0a64466a6a0640029000111a9aa80800111299a982a999ab9a3371e0040120ae0a"
      , "c2600e0022600c006640026aa0a44466a6a0620029000111a9aa80780111299a982a1"
      , "99ab9a3371e00400e0ac0aa20022600c006446a60060044444444444a66a6a07a666a"
      , "a605424002a0524a66a60ae666ae68cdc780600082c82c09a8200008a81f8019082c8"
      , "82b911111111109199999999980080580500480400380300280200180110009109198"
      , "008018011000911091998008020018011000889109198008018010890009109198008"
      , "018011000891091980080180109000891091980080180109000891091980080180109"
      , "000890911180180208911001089110008900090911111118038041109111111198030"
      , "048041091111111802804091111110020911111100191091111111980100480411091"
      , "11111198008048041000899a80491299a9a80b001108018800a80a990009aa8181108"
      , "911299a9a80900089a9a80600191000910999a9a807002910011802001199aa980389"
      , "000802802000909111180200291091111980180300291091111980100300290911118"
      , "0080290008919a80191199a9a80e001910010010009a9a80d00091000891091980080"
      , "18010900091b9233355300312001714004664466004646e48cc094004014d4c08000c"
      , "888008cc008dc91a9810001911000998011b923530200032220030015006500748900"
      , "320013550252211222533535007001100222133005002333553007120010050040013"
      , "200135502422122253353500600215335350060011027221028221533535008003102"
      , "8221533530293300700400213335300912001007003001102a1122002122122330010"
      , "040031200122353003002223530050032232335301000523353011004253353025333"
      , "573466e3c00800409c0985400c409880988cd4c044010809894cd4c094ccd5cd19b8f"
      , "00200102702615003102615335350090032153353500a00221335300e0022335300f0"
      , "022335301300223353014002233019002001202923353014002202923301900200122"
      , "2029222335301100420292225335302a333573466e1c01800c0b00ac54cd4c0a8ccd5"
      , "cd19b8700500202c02b13301a004001102b102b102415335350090012102410242212"
      , "330010030022001121223002003112200112001212230020032221223330010050040"
      , "0320012122300200321223001003200122333573466e1c00800405004c88ccd5cd19b"
      , "8f002001013012133500222533530100021012100100f122123300100300212001232"
      , "32323333573466e1cd55cea801a400046660166eb8d5d0a80198061aba15002375c6a"
      , "e84d5d1280111931a980399ab9c009008006005135744a00226aae7940044dd5000a4"
      , "c2400240029201035054310022212333001004003002200123253353006333573466e"
      , "21400400c02001c58540044dd6800a4000640026aa00c444a66a600a666ae68cdc400"
      , "1241000800e00c266e2c0080044cc00ccdc1801241000866e2ccdc300124100080024"
      , "a66a6004666ae68cdc40008028020018a4000200224400424400240029040497a0088"
      , "919180080091198019801001000a45004881004881004800122100480001"
      , "\""
      ]
