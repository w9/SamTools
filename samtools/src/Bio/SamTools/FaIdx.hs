-- | Fetch sequences from an indexed fasta file
module Bio.SamTools.FaIdx ( InHandle, filename
                          , open
                          , fetch
                          )
       where

import Control.Concurrent.MVar
import Control.Monad
import qualified Data.ByteString.Char8 as BS

import Foreign.Marshal.Alloc
import Foreign.Ptr
import Foreign.Storable

import Bio.SamTools.LowLevel

-- | Input handle for an indexed fasta file
data InHandle = InHandle { filename :: !FilePath -- ^ Name of the fasta file
                         , faidx :: !(MVar (Ptr FaIdxInt))
                         }
                
-- | Open an indexed fasta file
open :: FilePath -> IO InHandle
open name = do 
  f <- faiLoad name
  when (f == nullPtr) $ ioError . userError $ "Error opening indexed Fasta file " ++ show name
  mv <- newMVar f
  addMVarFinalizer mv (finalizeFaIdx mv)
  return $ InHandle { filename = name, faidx = mv }
  
finalizeFaIdx :: MVar (Ptr FaIdxInt) -> IO ()
finalizeFaIdx mv = modifyMVar mv $ \fai -> do
  unless (fai == nullPtr) $ faiDestroy fai
  return (nullPtr, ())

-- | Fetch a region specified by sequence name and coordinates
fetch :: InHandle -> BS.ByteString -- ^ Sequence name
         -> (Int, Int) -- ^ (Starting, ending) position, 0-based 
         -> IO BS.ByteString
fetch inh name (start, end) = withMVar (faidx inh) $ \fai ->
  BS.useAsCString name $ \cname ->
  alloca $ \lp -> do
    s <- faiFetchSeq fai cname start end lp
    l <- liftM fromIntegral . peek $ lp
    sout <- BS.packCStringLen (s, l)
    free s
    return sout