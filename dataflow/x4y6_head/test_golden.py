import unittest
from golden import Mac, Reference

class Tests(unittest.TestCase):
    def test_unsigned_fold_and_bubbles(self):
        m=Mac()
        expected=0
        products=[]
        queue=[None,None]
        for i in range(20003):
            start=i<20000 and i%7!=0
            a,b=i%16,(i*11)%16
            queue.append(a*b if start else None)
            product=queue.pop(0)
            done=0
            if product is not None:
                products.append(product)
                if len(products)==16:
                    expected=(expected+sum(products))&0xffffff
                    products=[]
                    done=1
            self.assertEqual(m.step(start,a,b),(expected,done))

    def test_wrap(self):
        m=Mac()
        m.acc=0xfffff0
        for _ in range(16):
            m.step(1,15,15)
        m.step(0,0,0)
        self.assertEqual(m.step(0,0,0),((0xfffff0+16*225)&0xffffff,1))

    def test_unknown_propagates(self):
        m=Mac()
        for i in range(16):
            m.step(1,None if i==4 else 0,1)
        m.step(0,0,0)
        self.assertEqual(m.step(0,0,0),(None,1))

    def test_zero_masks_unknown(self):
        m=Mac()
        for _ in range(16):
            m.step(1,None,0)
        m.step(0,0,0)
        self.assertEqual(m.step(0,0,0),(0,1))

    def test_mismatch_fails(self):
        with self.assertRaises(AssertionError):
            Reference().check(1,"mutation",1,0)

if __name__=="__main__":
    unittest.main()
