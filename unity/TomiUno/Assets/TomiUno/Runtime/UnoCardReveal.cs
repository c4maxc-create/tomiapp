using UnityEngine;

namespace Tomi.Uno
{
    public sealed class UnoCardReveal : MonoBehaviour
    {
        public GameObject Front, Back;
        public void ShowFace(bool faceUp)
        {
            if (Front != null) Front.SetActive(faceUp);
            if (Back != null) Back.SetActive(!faceUp);
        }
    }
}
