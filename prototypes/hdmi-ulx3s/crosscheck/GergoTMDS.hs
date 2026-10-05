-- Faithful transliteration of tmdsEncode1 from Gergo Erdi's clash-flappysquare
-- (branch ulx3s-hdmi, target/ulx3s/src/Hardware/ULX3S/TMDS.hs, MIT), with Clash types
-- replaced: Signed 4 by an Int wrapped to [-8,7] after every operation, BitVector by Int.
-- Purpose: measure how it compares with the DVI 1.0 flowchart. Prints, per (acc, d), the word.
import Data.Bits
import Text.Printf

wrap4 :: Int -> Int
wrap4 x = ((x + 8) `mod` 16) - 8

-- Clash's (xs :< x) splits off the LAST element of a Vec; bitCoerce BitVector 8 -> Vec 8 Bit
-- puts the MSB at index 0, so the last element is bit 0 (LSB).
-- scanr f x xs: result[last] = x = d0; result[i] = f (xs!!i) (result[i+1]).
-- In bit terms: q[k] = d[k] `op` q[k-1], q[0] = d[0].
stage1 :: (Int -> Int -> Int) -> Int -> Int
stage1 op d = go 1 (d .&. 1) (d .&. 1)
  where go k prev acc | k == 8 = acc
                      | otherwise = let b = op (bitAt d k) prev in go (k+1) b (acc .|. (b `shiftL` k))
bitAt x k = (x `shiftR` k) .&. 1

encode :: Int -> Int -> (Int, Int)
encode acc d = (wrap4 (acc + accN), word)
  where
    pop = popCount d
    (tag1, op) | pop > 4 || pop == 4 && testBit d 1 = (False, \a b -> 1 - xor a b)
               | otherwise = (True, xor)
    s1 = stage1 op d
    pop1 = popCount s1
    popDiff = wrap4 (2 * wrap4 (wrap4 pop1 - 4))
    (invert, acc')
      | acc == 0 || pop1 == 4 = (not tag1, if tag1 then popDiff else wrap4 (negate popDiff))
      | acc > 0 && pop1 > 4 || acc < 0 && pop1 < 4 = (True, wrap4 ((if tag1 then 0 else 2) - popDiff))
      | otherwise = (False, wrap4 ((if tag1 then (-2) else 0) + popDiff))
    accN = acc'
    s2 = if invert then complement s1 .&. 0xff else s1
    word = (fromEnum invert `shiftL` 9) .|. (fromEnum tag1 `shiftL` 8) .|. s2

main :: IO ()
main = mapM_ (\(a,d) -> let (a', w) = encode a d in printf "%d %d %d %d\n" a d w a') [ (a,d) | a <- [-8..7], d <- [0..255] ]
